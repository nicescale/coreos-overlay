# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="Csphere Product"
HOMEPAGE="https://csphere.cn/"

CROS_WORKON_PROJECT="nicescale/csphere"
CROS_WORKON_LOCALNAME="csphere"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
    KEYWORDS="~amd64 ~arm64"
else
    CROS_WORKON_COMMIT="3cfe0896330ce5abfe661c74e4c9cc21bbba333e" # v0.13.0
    KEYWORDS="amd64 arm64"
fi

inherit  systemd cros-workon

LICENSE="Apache-2.0"
SLOT="0"
IUSE=""

CDEPEND="
"

DEPEND="
	>=dev-lang/go-1.3
	csphere/go-bindata
	csphere/prometheus
"

RDEPEND="
"

RESTRICT="installsources strip"

src_prepare() {
	[ -d assets ] && rm -rf assets
	( gzip -dc ${FILESDIR}/assets-latest.tgz | tar x ) || die "uncompress assets-latest.tgz"
	cp -r terminal/assets/* assets
	/build/amd64-usr/usr/bin/go-bindata -nomemcopy -prefix=assets \
		-o views/assets.go -pkg=views ./assets || die "go-bindata on assets views"
	rm -rf assets
}

src_compile() {
	rm -rf /tmp/src/github.com/nicescale/csphere
	mkdir -p /tmp/src/github.com/nicescale/csphere 
	cp -a . /tmp/src/github.com/nicescale/csphere/
	rm -rf /tmp/etc/
	mkdir -p /tmp/etc/
	cp -a ./tools/etc/* /tmp/etc/ || die "copy tools/etc"
	GOPATH=/tmp:/tmp/src/github.com/nicescale/csphere/Godeps/_workspace/ \
		CGO_ENABLED=0 GOOS=linux \
		go build -a -installsuffix cgo -ldflags="-w" \
		-o /tmp/csphere || die  "build csphere"
	cd tools/init/
	GOPATH=/tmp:/tmp/src/github.com/nicescale/csphere/Godeps/_workspace/ \
		CGO_ENABLED=0 GOOS=linux \
		go build -a -installsuffix cgo -ldflags="-w" \
		-o /tmp/csphere-init || die "build csphere-init"
	mkdir -p /tmp/csphere-mongo/
	tar -xzf ${FILESDIR}/csphere-mongo.tgz -C /tmp/csphere-mongo/
}

src_install() {
	newbin /tmp/csphere csphere
	newbin /tmp/csphere-init csphere-init
	newbin /tmp/csphere-mongo/bin/mongod mongod
	newbin /tmp/csphere-mongo/bin/mongo  mongo

	dodir /usr/share/oem/lib64/
	insinto /usr/share/oem/lib64/
	doins -r /tmp/csphere-mongo/lib64/*

	dodir /usr/lib/csphere/etc/
	insinto /usr/lib/csphere/etc/
	doins -r /tmp/etc/*

	dosym /usr/lib/csphere/etc/mongodb.conf  /etc/mongodb.conf 
	dosym /usr/lib/csphere/etc/process-agent.json /etc/process-agent.json 
	dosym /usr/lib/csphere/etc/process.json /etc/process.json 
	# dosym /usr/lib/csphere/etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

	systemd_dounit "${FILESDIR}/csphere.service"
}

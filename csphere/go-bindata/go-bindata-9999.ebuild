# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="go-bindata"
HOMEPAGE="https://github.com/jteeuwen/go-bindata"

CROS_WORKON_PROJECT="mountkin/go-bindata"
CROS_WORKON_LOCALNAME="go-bindata"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64"
else
	CROS_WORKON_COMMIT="3e90fea08bf6644f483d50e967581e898f40009d"
	KEYWORDS="amd64 arm64"
fi

inherit  cros-workon

LICENSE="Apache-2.0"
SLOT="0"
IUSE=""

CDEPEND="
"

DEPEND="
	>=dev-lang/go-1.3
"

RDEPEND="
"

RESTRICT="installsources strip"

src_compile() {
	mkdir -p /tmp/src/github.com/mountkin/go-bindata     
	cp -a . /tmp/src/github.com/mountkin/go-bindata
	cd go-bindata/
	(
	type -a go
	go version
	/usr/bin/go version || true
	/build/amd64-usr/usr/bin/go  version || true
	) 2>&1 | tee /tmp/gobin.go-bindata.txt
	GOPATH=/tmp go build  -o /tmp/go-bindata
	git log --pretty=format:"%h - %an, %ai : %s" -1 | tee /tmp/csphere-product-go-bindata.txt
}

src_install() {
	einfo "in src_install()"
	newbin /tmp/go-bindata go-bindata 
}

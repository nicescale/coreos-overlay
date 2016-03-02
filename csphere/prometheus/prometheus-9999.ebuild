# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="prometheus"
HOMEPAGE="http://prometheus.io/"

CROS_WORKON_PROJECT="prometheus/prometheus"
CROS_WORKON_LOCALNAME="prometheus"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64"
else
	CROS_WORKON_COMMIT="db4df06414c2c602bd60bf28f4ec0242d11949f3"
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
	cd web
	../scripts/embed-static.sh static templates | gofmt > blob/files.go
	cd ../
	mkdir -p /tmp/src/github.com/prometheus/prometheus
    cp -a . /tmp/src/github.com/prometheus/prometheus
    GOPATH=/tmp:/tmp/src/github.com/prometheus/prometheus/Godeps/_workspace/ \
		CGO_ENABLED=0 GOOS=linux  \
		go build -a -installsuffix cgo -ldflags="-X main.buildVersion 0.14.0 \
			-X main.buildRevision $(git rev-parse --short HEAD) \
			-X main.buildBranch master \
			-X main.buildUser mountkin@gmail.com \
			-X main.buildDate '$(date)' \
			-X main.goVersion 1.4.1 -w"  \
			-o /tmp/prometheus # rpm: /tmp/prometheus
	git log --pretty=format:"%h - %an, %ai : %s" -1 | tee /tmp/csphere-product-prometheus.txt
}

src_install() {
	newbin /tmp/prometheus prometheus 
}

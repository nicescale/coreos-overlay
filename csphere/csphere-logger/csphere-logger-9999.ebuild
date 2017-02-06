# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="Csphere Docker Log Driver"
HOMEPAGE="https://csphere.cn/"

CROS_WORKON_PROJECT="nicescale/csphere-logger"
CROS_WORKON_LOCALNAME="csphere-logger"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
    KEYWORDS="~amd64 ~arm64"
else
    CROS_WORKON_COMMIT="-"   # use HEAD, tell ebuild to skip another checkout
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
"

RDEPEND="
"

RESTRICT="installsources strip"

src_compile() {
	rm -rf /tmp/src/github.com/nicescale/csphere-logger
	mkdir -p /tmp/src/github.com/nicescale/csphere-logger
	cp -a . /tmp/src/github.com/nicescale/csphere-logger/
	GOPATH=/tmp:/tmp/src/github.com/nicescale/csphere-logger/vendor/ \
	CGO_ENABLED=0 GOOS=linux \
		go build -v -ldflags "-w" \
		-o /tmp/csphere-logger || die "build csphere-logger"  # rpm: /tmp/csphere-logger
	git log --pretty=format:"%h - %an, %ai : %s" -1	| tee /tmp/csphere-product-csphere-logger.txt
}

src_install() {
	newbin /tmp/csphere-logger csphere-logger
}
# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="skydns"
HOMEPAGE="https://github.com/skynetservices/skydns"

CROS_WORKON_PROJECT="zhang0137/skydns"
CROS_WORKON_LOCALNAME="skydns"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64"
else
	CROS_WORKON_COMMIT="9917c72b881d2f73079953f7838836ec3a3b446d"
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
	mkdir -p /tmp/src/github.com/zhang0137/skydns
	cp -a . /tmp/src/github.com/zhang0137/skydns
	(
	type -a go
	go version
	/usr/bin/go version || true
	/build/amd64-usr/usr/bin/go  version || true
	) 2>&1 | tee /tmp/gobin.skydns.$(date +%s).txt
	GOPATH=/tmp:/tmp/src/github.com/zhang0137/skydns/Godeps/_workspace/ \
		CGO_ENABLED=0 GOOS=linux  \
		go build -o /tmp/skydns # rpm: /tmp/skydns
	git log --pretty=format:"%h - %an, %ai : %s" -1 | tee /tmp/csphere-product-skydns.txt
}

src_install() {
	newbin /tmp/skydns skydns 
}

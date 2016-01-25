# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="Csphere Docker IPAM"
HOMEPAGE="https://csphere.cn/"

CROS_WORKON_PROJECT="nicescale/netplugin"
CROS_WORKON_LOCALNAME="netplugin"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
    KEYWORDS="~amd64 ~arm64"
else
    CROS_WORKON_COMMIT="-"  # use HEAD, tell ebuild to skip another checkout
    # CROS_WORKON_COMMIT="74545015e52db52b176e0c3c394cb4e31b0b7661"  # csphere 1.0.0
    # CROS_WORKON_COMMIT="6b7649362330c6f9d999ef1a9f04f1672357b368"  # csphere 1.0.1
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
	rm -rf /tmp/src/github.com/nicescale/netplugin
	mkdir -p /tmp/src/github.com/nicescale/netplugin
	cp -a . /tmp/src/github.com/nicescale/netplugin/
	GIT_COMMIT=$(git rev-parse --short HEAD)
	if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  		GIT_COMMIT=${GIT_COMMIT}-dirty
	fi
	GOPATH=/tmp:/tmp/src/github.com/nicescale/netplugin/Godeps/_workspace/ \
		CGO_ENABLED=0 GOOS=linux \
		go build -a -installsuffix cgo -ldflags=" -X main.gitCommit='$GIT_COMMIT' -w" \
		-o /tmp/net-plugin || die  "build netplugin"
	git log --pretty=format:"%h - %an, %ai : %s" -1 | tee /tmp/csphere-product-netplugin.txt
}

src_install() {
	newbin /tmp/net-plugin net-plugin
}

# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="COS Test Tool"
HOMEPAGE="https://csphere.cn/"

CROS_WORKON_PROJECT="zhang0137/costest"
CROS_WORKON_LOCALNAME="costest"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
    KEYWORDS="~amd64 ~arm64"
else
    CROS_WORKON_COMMIT="885085beaf22c4bed1e45bce6be46fe56acc06af"
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
	make build  || die "build costest"
	cp -a stress.toml /tmp/stress.toml
	cp -a costest /tmp/costest
}

src_install() {
	newbin /tmp/costest costest

	dodir /usr/lib/csphere/etc/
	insinto /usr/lib/csphere/etc/
	doins /tmp/stress.toml
	
	dosym /usr/lib/csphere/etc/stress.toml /etc/csphere/stress.toml
}

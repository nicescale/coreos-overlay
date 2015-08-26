# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

DESCRIPTION="mongodb"
HOMEPAGE="https://github.com/mongodb/mongo"

CROS_WORKON_PROJECT="mongodb/mongo"
CROS_WORKON_LOCALNAME="mongo"
CROS_WORKON_REPO="git://github.com"

if [[ "${PV}" == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64"
else
	CROS_WORKON_COMMIT="b40106b36eecd1b4407eb1ad1af6bc60593c6105"
	KEYWORDS="amd64 arm64"
fi

inherit  cros-workon

LICENSE="Apache-2.0"
SLOT="0"
IUSE=""

CDEPEND="
"

DEPEND="
"

RDEPEND="
"

RESTRICT="installsources strip"

src_compile() {
	scons mongod
}

src_install() {
	newbin /path/to/build/mongod mongod 
}

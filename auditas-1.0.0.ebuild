# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Audio library integrity verification and management suite"
HOMEPAGE="https://github.com/cabeanderson/auditas"
SRC_URI="https://github.com/cabeanderson/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="imaging mp3 replaygain"

RDEPEND="
	app-shells/bash
	media-libs/flac
	media-video/ffmpeg
	sys-apps/coreutils
	sys-apps/findutils
	sys-apps/gawk
	sys-apps/grep
	sys-apps/sed
	imaging? ( media-gfx/imagemagick )
	mp3? (
		media-sound/mp3val
		media-sound/vbrfix
	)
	replaygain? ( media-sound/loudgain )
"

src_install() {
	# Install library and logic scripts to /usr/share/auditas
	insinto /usr/share/${PN}
	doins -r lib logic

	# Install main script (handle both auditas and auditas.sh naming)
	if [[ -f auditas ]]; then
		doins auditas
		fperms +x /usr/share/${PN}/auditas
	elif [[ -f auditas.sh ]]; then
		newins auditas.sh auditas
		fperms +x /usr/share/${PN}/auditas
	fi

	# Ensure logic scripts are executable
	fperms +x /usr/share/${PN}/logic/*.sh

	# Create a wrapper in /usr/bin
	newbin - auditas <<-EOF
#!/bin/bash
exec /usr/share/${PN}/auditas "\$@"
EOF

	# Install bash completion
	newbashcomp auditas_completion.bash auditas

	# Docs
	dodoc README.md CHANGELOG.md CONTRIBUTING.md ARCHITECTURE.md
}
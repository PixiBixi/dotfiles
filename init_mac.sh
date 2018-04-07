#!/bin/sh

export HOMEBREW_CASK_OPTS="--appdir=/Applications"
xcode-select --install

ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

brew install aria2
brew install coreutils
brew install ffmpeg
brew install htop
brew install iftop
brew install iperf3
brew install iproute2mac
brew install lolcat
brew install mackup
brew install mediainfo
brew install mkvtoolnix
brew install mpv
brew install mtr
brew install mycli
brew install ncdu
brew install pastebinit
brew install tree
brew install wget
brew install wget
brew install whois
brew install wine
brew install youtube-dl

brew tap caskroom/cask

# Core Functionality
echo Install Core Apps
brew cask install alfred
brew cask install dropbox
brew cask install little-snitch
brew cask install vlc
brew cask install iterm2
brew cask install java
brew cask install tunnelblick
brew cask install daisydisk
brew cask install telegram
brew cask install evernote

# Development & Network
brew install grv
brew install git
brew install vim
brew install git-quick-stats
brew install visual-studio-code
brew install httpie

brew cask install gns3
brew cask install wireshark-chmodbpf
brew cask install royal-tsx


# Google Slavery
brew cask install google-chrome

# Nice to have
brew cask install firefox
brew cask install spotify
brew cask install ramme
brew cask install spotify-notifications

# Link Apps
brew cask alfred link
brew link mpv

# cleanup
brew cleanup --force
brew cask cleanup --force
rm -f -r /Library/Caches/Homebrew/*
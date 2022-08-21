PLATFORM=$(uname)


if [[ $PLATFORM == "Linux" ]]; then
	echo "Install vim & git"
	apt-get install vim git-core
else
	# If brew is already installed
	if [[ $(brew &> /dev/null || echo $?) == 1 ]]; then
		brew install vim git
	else
		echo "Install XCode (Depends for brew)"
		xcode-select --install
		echo "Install Brew"
		ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
		echo "Install vim"
		brew install vim
	fi
fi

echo "Install Vundle"
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

echo "Install vimrc"
git clone https://github.com/PixiBixi/dotfiles
cp dotfiles/.vimrc $HOME/
vim +PluginInstall +qall

#!/usr/bin/env bash
#TODO: Rewrite it 100%

xcode-select --install

echo "🔵  Setting up brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo "Installation OK ✅\n"

# Install oh-my-zsh
echo "Cloning oh-my-zsh..."
[ -d "${HOME}"/.oh-my-zsh ] || sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "Installation OK ✅\n"

echo "🔵  Setting up .zshrc"
cp -f .zshrc ~/.zshrc
echo "Installation OK ✅\n"


# Install ZSH plugins
echo "Cloning zsh plugins..."
[ -d "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions ] || git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions
[ -d "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
echo "Installation OK ✅\n"

echo "Install Brew applications"
curl -s https://raw.githubusercontent.com/PixiBixi/dotfiles/master/Brewfile > ~/Brewfile
brew bundle install

echo "🔵  Setting up fzf"
[ -f /opt/homebrew/opt/fzf/install ] && /opt/homebrew/opt/fzf/install --all

echo "🔵  Setting up kubeswitch"
[ ! -d ~/.kube ] && cp -r .kube ~/.kube || cp .kube/switch-config.yaml .kube/

echo "🔵  Setting up krew plugins"
kubectl krew install < ./Plugins_Krew
echo "Installation OK ✅\n"

echo "🔵  Setting up Wezterm"
cp ./.wezterm.lua ~/.wezterm.lua
echo "Installation OK ✅\n"

echo "Don't forget to split your kubeconfig file into several. You can use konfig to corneliusweig/konfig to split it"

echo "🔵  Bootstrap architecture folders"
mkdir -p ~/Documents/{perso,work}/git/
cp ./.gitconfig_perso ~/
cp ./.gitconfig_work ~/
echo "Installation OK ✅\n"

echo "🔵  Install NPM packages"
xargs npm install --global < ./npmfile
echo "Installation OK ✅\n"

echo "🔵 Install Gem packages "
cat ./gemlist | xargs -L 1 gem install
echo "Installation OK ✅\n"

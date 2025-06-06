#!/usr/bin/env bash
#TODO: Rewrite it 100%

xcode-select --install

echo "🔵  Setting up zsh"

# Install oh-my-zsh
printf "Cloning oh-my-zsh..."
[ -d "${HOME}"/.oh-my-zsh ] || sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
printf " ✅\n"

# Install ZSH plugins
printf "Cloning zsh plugins..."
[ -d "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions ] || git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-autosuggestions
[ -d "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"/plugins/zsh-syntax-highlighting
printf " ✅\n"

printf "Install Brew applications"
curl -s https://raw.githubusercontent.com/PixiBixi/dotfiles/master/Brewfile > ~/Brewfile
brew bundle install

echo "🔵  Setting up fzf"
[ -f /opt/homebrew/opt/fzf/install ] && /opt/homebrew/opt/fzf/install --all


echo "🔵  Setting up kubeswitch"
[ ! -d ~/.kube ] && cp -r .kube ~/.kube || cp .kube/switch-config.yaml .kube/

echo "🔵  Setting up krew plugins"
kubectl krew install < ./Plugins_Krew


echo "🔵  Setting up Wezterm"
cp ./.wezterm.lua ~/.wezterm.lua

echo "Don't forget to split your kubeconfig file into several. You can use konfig to corneliusweig/konfig to split it"
printf " ✅\n"

echo "🔵  Bootstrap architecture folders"
mkdir -p ~/Documents/{perso,work}/git/
cp ./.gitconfig_perso ~/Documents/perso/git
cp ./.gitconfig_work ~/Documents/work/git

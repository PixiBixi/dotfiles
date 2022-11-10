# dotfiles
All my useful dotfiles

Simply download and run the script to install my dotfile

## Requirements

### zsh

Notre configuration zsh est évidemment basée sur celle qui est fournie en défaut par [oh-my-zsh](https://ohmyz.sh/). Pour l'installer, une simple ligne :

```
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Cepenant, nous utilisons un plugin custom : zsh-syntax-highlighting. Son installation est très simple

```shell
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### vim

If you want to use RFC plugin, you must to compile your vim with ruby support, and install the nokogiri gem

```
gem install nokogiri
curl https://raw.githubusercontent.com/PixiBixi/dotfiles/master/init.sh | bash
```

### ssh

In order to user `ControlMaster`, we need to create `~/.ssh/private` folder

```
mkdir ~/.ssh/private
```

### Git

`git h` uses an external software, lets install it

```
gem install giturl
```

## MacOS Specific

Few things only for MacOS

### iTerm 2

  * [Theme](https://github.com/sindresorhus/iterm2-snazzy) for iTerm 2
  * Use **Natural Key Mapping**
    * Preference
	* Profile, mainly use default
	* Keys
	* Key Mapping
	* Presets > Use _Natural Text Editing_

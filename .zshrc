export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PATH="$PATH:/Applications/platform-tools"
export PATH="/Users/shuya/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PATH=$PATH:/Users/shuya/Documents
export PATH="/Users/shuya/.local/bin:$PATH"
export PATH=$PATH:~/.yarn/bin
export PATH=$PATH:/Users/shuya/opt/homebrew/Cellar/opus/1.4/lib/

export DYLD_LIBRARY_PATH=/Users/shuya/opt/homebrew/Cellar/opus/1.4/lib/:$DYLD_LIBRARY_PATH
export LDFLAGS="-L/opt/homebrew/opt/zlib/lib"
export CPPFLAGS="-I/opt/homebrew/opt/zlib/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/zlib/lib/pkgconfig"
export DYLD_LIBRARY_PATH="/Users/shuya/opt/homebrew/Cellar/libusb/1.0.26/lib:$DYLD_LIBRARY_PATH"
export LDFLAGS="-L/usr/local/opt/zlib/lib"
export CPPFLAGS="-I/usr/local/opt/zlib/include"
export PKG_CONFIG_PATH="/usr/local/opt/zlib/lib/pkgconfig"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

PATH=”${PATH}:$HOME/.nodebrew/current/bin”



if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

eval "$(starship init zsh)"
SPACESHIP_PROMPT_ASYNC=FALSE
eval "$(direnv hook zsh)"
. "$HOME/.local/bin/env"
eval "$(uv generate-shell-completion zsh)"

alias ur='uv run python'
alias vi='nvim'
alias sftp='sftp -P 25288 shuya@nitfccuda.mydns.jp'
alias pp='poetry run python'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<


eval "(neofetch)"



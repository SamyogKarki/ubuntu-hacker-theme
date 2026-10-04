# >>> hacker-theme >>>
# Green hacker prompt:  ┌─[user@host]─[~/dir]─[git:branch]─[✔]─[⏱ 4.2s]        [22:41]
#                       └──╼ $
# Timestamp of when the current command started (set by the DEBUG trap, cleared by the prompt).
trap '[[ -z $__hk_t0 ]] && __hk_t0=$EPOCHREALTIME' DEBUG
__hk_prompt() {
  local s=$? G='\[\e[1;32m\]' D='\[\e[0;32m\]' Y='\[\e[1;93m\]' R='\[\e[1;31m\]' N='\[\e[0m\]'
  local mark="${G}✔"; [ $s -ne 0 ] && mark="${R}✘ $s"
  # how long the last command took, shown only when it was 2s or more
  local took=""
  if [[ -n $__hk_t0 ]]; then
    local ms=$(( (${EPOCHREALTIME/./} - ${__hk_t0/./}) / 1000 ))
    if (( ms >= 2000 )); then
      if (( ms >= 60000 )); then took="$((ms / 60000))m$(( (ms / 1000) % 60 ))s"
      else took="$((ms / 1000)).$(( (ms % 1000) / 100 ))s"; fi
      took="${D}─[${Y}⏱ ${took}${D}]"
    fi
  fi
  unset __hk_t0
  local branch git=""
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [[ -n $branch ]] && git="${D}─[${G}git:${branch}${D}]"
  # clock pinned to the right edge (cursor saved, moved, restored, so it takes no prompt width)
  local clock="\[\e7\e[$((${COLUMNS:-80} - 6))G\e[0;32m[\A]\e8\]"
  PS1="${clock}${D}┌─[${G}\u${D}@${G}\h${D}]─[${G}\w${D}]${git}─[${mark}${D}]${took}\n${D}└──╼ ${G}\$ ${N}"
}
PROMPT_COMMAND=__hk_prompt
# Unknown commands: hacker-style error, then installed look-alikes, then Ubuntu's install hint if any
command_not_found_handle() {
  printf '\e[1;31m[ACCESS DENIED]\e[0;32m command \e[1;32m%s\e[0;32m not recognised\e[0m\n' "$1" >&2
  local close
  close=$(compgen -c | sort -u | python3 -c 'import sys,difflib; print(" ".join(difflib.get_close_matches(sys.argv[1], sys.stdin.read().split(), n=3, cutoff=0.6)))' "$1" 2>/dev/null)
  [[ -n $close ]] && printf '\e[0;32m  did you mean: \e[1;32m%s\e[0m\n' "$close" >&2
  if [[ -x /usr/lib/command-not-found ]]; then
    local hint
    hint=$(/usr/lib/command-not-found -- "$1" 2>&1 | grep -m1 '^sudo apt install [^<]')
    [[ -n $hint ]] && printf '\e[0;32m  install it with: \e[1;32m%s\e[0m\n' "$hint" >&2
  fi
  return 127
}
export LS_COLORS="di=1;32:ln=0;36:ex=1;92:*.sh=0;92"
export BAT_THEME=ansi
alias matrix='cmatrix -b -u 4 -C green'
# cat with syntax colours; falls back to the real cat when given options bat doesn't know (cat -v, -A, -n...)
cat() {
  if [[ $1 == -* ]]; then command cat "$@"; else batcat --paging=never --style=plain "$@"; fi
}
alias bat='batcat'
alias ls='eza --group-directories-first'
alias ll='eza -lah --group-directories-first --git'
alias tree='eza --tree --group-directories-first'
alias top='btop'
# Brave theme (only defined when the installer found Brave)
[[ -f $HOME/brave-hacker-theme/manifest.json ]] && alias brave='brave --load-extension=$HOME/brave-hacker-theme'
# type text out one character at a time
__hk_type() {
  local i
  for ((i = 0; i < ${#1}; i++)); do printf '%s' "${1:i:1}"; sleep 0.006; done
  printf '\n'
}
if [[ $- == *i* ]] && [ -z "$HK_BANNER_SHOWN" ]; then
  export HK_BANNER_SHOWN=1
  printf '\e[0;32m'
  __hk_type "[*] Initialising secure shell..."
  __hk_type "[*] Encrypted tunnel established"
  printf '\e[1;32m'
  __hk_type "[+] Access granted. Welcome back, ${USER}."
  printf '\e[0m'
  fastfetch
fi
# <<< hacker-theme <<<

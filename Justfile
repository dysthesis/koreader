# crengine is a submodule, and flake refs omit those unless asked.
flake := ".?submodules=1"

default:
    @just --list

# Fuzz the Knuth-Plass line breaker until interrupted; WORKDIR keeps the corpus and crashes, so re-runs resume.
fuzz workdir="./kp-fuzz" *args:
    nix run '{{ flake }}#kp-fuzz' -- {{ workdir }} {{ args }}

# Static analysis and sanitiser checks.
check *args:
    nix flake check '{{ flake }}' {{ args }}

#!/usr/bin/env bash

set -Eeuo pipefail

function err {
    printf "\e[31m%s\e[39m\n" "$1" >&2
}

command -v mapfile > /dev/null || (err "Requires modern bash; $BASH_VERSION is too old"; exit 1)

if [ $# != 3 ]; then
    echo "Usage: $0 n secret key_ids" >&2
    exit 1
fi

readonly SECRET=$2

function cleanup {
    code=$?

    [[ $code == 0 ]] || err "Exiting with error code $code"

    echo -n "Cleaning up... "
    rm "$SECRET".??? 2> /dev/null || true
    rm "$SECRET".???.gpg 2> /dev/null || true
    rm "$SECRET".checksums 2> /dev/null || true
    echo "done"

    exit $code
}

trap cleanup ERR

function sha_hash {
    if command -v shasum > /dev/null; then
        shasum -a 256 "$@"
    elif command -v sha256sum > /dev/null; then
        sha256sum "$@"
    else
        err "Failed to find a suitable hash program"
        return 1
    fi
}

function main {
    local -r n="$1"
    local -r secret="$2"
    local -r key_ids_fd="$3"

    [[ -e "$secret" ]] || (err "$secret not found" && exit 1)
    [[ -e "$key_ids_fd" ]] || (err "$key_ids_fd not found" && exit 1)

    mapfile -t key_ids < "$key_ids_fd"

    local -r m=${#key_ids[@]}

    gfsplit -n "$n" -m "$m" "$secret"
    echo "Split secret \"$secret\" using a $n-of-$m scheme"

    sha_hash "$secret" "$secret".??? > "$secret".checksums
    echo "Hashes added to $secret.checksums"

    local index=0
    for file in "$secret".???; do
        gpg --encrypt --trust-model always --recipient "${key_ids[$index]}" "$file"
        echo -e "$index:\tEncrypted $file against ${key_ids[$index]}"
        index=$((index + 1))
    done

    tar -cvjf "$secret.tar.bz2" README "$secret".???.gpg "$secret".checksums
    echo "Output tarball: $secret.tar.bz2"

    cleanup
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi

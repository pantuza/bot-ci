# Common helper functions & environment variable defaults for all types of builds.

# Fail if an environment variable does not exist.
# ${1}: Environment variable.
# ${2}: Script file.
# ${3}: Line number.
require_environment_variable() {
  local variable_name="${1}"
  local variable_content="${!variable_name}"
  if [[ -z "${variable_content}" ]]; then
    >&2 echo "${variable_name} not set at ${2}:${3}, cannot continue!"
    >&2 echo "Maybe you need to source a script from ci/common."
    exit 1
  fi
}

# Output the current OS.
# Possible values are "osx" and "linux".
get_os() {
  local os="$(uname -s)"
  if [[ "${os}" == "Darwin" ]]; then
    echo "osx"
  else
    echo "linux"
  fi
}

require_environment_variable BUILD_DIR "${BASH_SOURCE[0]}" ${LINENO}

CI_TARGET=${CI_TARGET:-$(basename ${0%.sh})}
CI_OS=${TRAVIS_OS_NAME:-$(get_os)}
MAKE_CMD=${MAKE_CMD:-"make -j2"}
GIT_NAME=${GIT_NAME:-marvim}
GIT_EMAIL=${GIT_EMAIL:-marvim@users.noreply.github.com}

# Check if currently performing CI or local build.
# ${1}: Task that is NOT executed if building locally.
#       Default: "installing dependencies"
# Return 0 if CI build, 1 otherwise.
is_ci_build() {
  if [[ ${CI} != true ]]; then
    echo "Local build, skip ${1:-installing dependencies}."
    return 1
  fi
}

# Clone a Git repository and check out a subtree.
# ${1}: Variable prefix.
clone_subtree() {(
  local prefix="${1}"
  local subtree="${prefix}_SUBTREE"
  local dir="${prefix}_DIR"
  local repo="${prefix}_REPO"
  local branch="${prefix}_BRANCH"

  require_environment_variable ${subtree} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${dir} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${repo} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${branch} "${BASH_SOURCE[0]}" ${LINENO}

  [ -d "${!dir}/.git" ] || git init "${!dir}"
  cd "${!dir}" 
  git rev-parse HEAD >/dev/null 2>&1 && git reset --hard HEAD

  is_ci_build "Git subtree" && {
    git config core.sparsecheckout true
    echo "${!subtree}" > .git/info/sparse-checkout
  }
  git checkout -B ${!branch}
  git pull --rebase --force git://github.com/${!repo} ${!branch}
)}

# Prompt the user to press a key to continue for local builds.
# ${1}: Shown message.
prompt_key_local() {
  if [[ ${CI} != true ]]; then
    echo "${1}"
    echo "Press a key to continue, CTRL-C to abort..."
    read -n 1 -s
  fi
}

# Commit and push to a Git repo checked out using clone_subtree.
# ${1}: Variable prefix.
commit_subtree() {(
  local prefix="${1}"
  local subtree="${prefix}_SUBTREE"
  local dir="${prefix}_DIR"
  local repo="${prefix}_REPO"
  local branch="${prefix}_BRANCH"

  require_environment_variable CI_TARGET "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable GIT_NAME "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable GIT_EMAIL "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${subtree} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${dir} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${repo} "${BASH_SOURCE[0]}" ${LINENO}
  require_environment_variable ${branch} "${BASH_SOURCE[0]}" ${LINENO}

  # Remove possible file name from full subtree path and change directory.
  local subtree_path="${!dir}${!subtree}"
  subtree_path=${subtree_path%/*}
  cd ${subtree_path}

  git add --all .

  [[ ${CI} == true ]] && {
    # Commit on Travis CI.
    if [[ -z "${GH_TOKEN}" ]]; then
      echo "GH_TOKEN not set, not committing."
      echo "To test pull requests, see instructions in README.md."
      return 1
    fi

    git config --local user.name ${GIT_NAME}
    git config --local user.email ${GIT_EMAIL}

    git commit -m "${CI_TARGET//-/ }: Automatic update." || true
    until (git pull --rebase git://github.com/${!repo} ${!branch} &&
           git push https://${GH_TOKEN}@github.com/${!repo} ${!branch} >/dev/null 2>&1 &&
           echo "Pushed to ${!repo} ${!branch}."); do
      echo "Retry pushing to ${!repo} ${!branch}."
      sleep 1
    done
    return
  } || prompt_key_local "Build finished, do you want to commit and push the results to ${!repo}:${!branch} (change by setting ${repo}/${branch})?" && {
    # Commit in local builds.
    git commit || true
    git push ssh://git@github.com/${!repo} ${!branch}
  }
)}

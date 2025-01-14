function pr_review_changes() {
    local branch_name=$1
    local current_branch=$(git branch --show-current)
    local stashed=false
    local base_branch=${2:-main}
    
    # Check for any changes (including untracked files)
    if [ -n "$(git status --porcelain --untracked-files=all)" ] || [ -n "$(git diff)" ] || [ -n "$(git diff --cached)" ]; then
        echo "Stashing local changes..."
        git stash push -m "Temporary stash before PR review"
        stashed=true
        echo "Local changes have been stashed"
    fi

    # First ensure we have latest main
    echo "Fetching and switching to $base_branch branch..."
    git fetch origin $base_branch:$base_branch
    git checkout $base_branch
    git pull origin $base_branch
    
    # Check if branch exists locally
    if ! git show-ref --verify --quiet refs/heads/$branch_name; then
        # If not local, check if it exists in remote
        if git ls-remote --exit-code origin $branch_name >/dev/null 2>&1; then
            echo "Branch '$branch_name' not found locally, but exists in remote. Fetching..."
            git fetch origin $branch_name:$branch_name
        else
            echo "Branch '$branch_name' not found locally or in remote"
            echo "Returning to $current_branch..."
            git checkout "$current_branch"
            if [ "$stashed" = true ]; then
                echo "Restoring your local changes..."
                git stash pop
            fi
            return 1
        fi
    fi
    
    # Checkout the PR branch
    git checkout $branch_name
    git pull origin $branch_name
    
    # Get the base branch commit
    base_commit=$(git merge-base $branch_name $base_branch)
    
    # Reset to base commit with changes in working directory
    git reset --mixed $base_commit
    
    echo "Changes from PR are now shown as uncommitted changes"
    echo "Enter 'r' to revert changes and return to your original branch ($current_branch)"
    echo "Enter 'q' to quit without reverting"
    
    read action
    if [ "$action" = "r" ]; then
        # First get list of untracked files
        local untracked_files=$(git ls-files --others --exclude-standard)
        
        # Reset hard to remove tracked changes
        git reset --hard
        
        # Remove untracked files if they exist
        if [ -n "$untracked_files" ]; then
            echo "Cleaning up untracked files from feature branch..."
            echo "$untracked_files" | xargs rm -f 2>/dev/null || true
        fi
        
	    git pull origin $branch_name
        echo "Returning to $current_branch..."
        git checkout "$current_branch"
        if [ "$stashed" = true ]; then
            echo "Restoring your local changes..."
            git stash pop
        fi
        echo "Synced with origin and returned to $current_branch"
    elif [ "$action" = "q" ]; then
        echo "Exiting without reverting. Use 'git reset --hard' manually when done"
    fi
}

# Enhanced autocompletion function that includes remote branches
_pr_review_changes() {
    local -a branches
    # Update remote branches info
    git fetch --quiet 2>/dev/null
    
    # Get both local and remote branches
    local_branches=(${(f)"$(git branch --format='%(refname:short)')"})
    remote_branches=(${(f)"$(git branch -r --format='%(refname:short)' | grep '^origin/' | sed 's/^origin\///')"})
    
    # Combine unique branches
    branches=($(printf "%s\n" "${local_branches[@]}" "${remote_branches[@]}" | sort -u))
    
    _describe 'branches' branches
}

# Register the completion function
compdef _pr_review_changes pr_review_changes

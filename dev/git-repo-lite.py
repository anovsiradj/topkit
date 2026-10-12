import sys
import os
import subprocess

def run_cmd(cmd, cwd=None, allow_fail=False):
	"""
	Executes system commands reliably across platforms (Windows/Linux/Mac).
	Uses array arguments to bypass shell-parsing issues on different terminals.
	"""
	print(f"Running: {' '.join(cmd)}")
	result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
	
	if result.returncode != 0 and not allow_fail:
		print(f"Error: {result.stderr.strip()}")
		raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)
	return result.stdout.strip()

def print_usage():
	"""
	Displays the interactive manual when the script is run without arguments.
	"""
	print("=" * 80)
	print(" 🛠️  GIT REPO LITE: CLI Automator for Minimum Size Clones & Updates")
	print("=" * 80)
	print("\nAVAILABLE COMMANDS:")
	print("  1. clone     Download a repository for the first time with minimum size.")
	print("  2. update    Pull the latest app and submodule updates.")
	print("  3. convert   Shrink an existing bloated local repository into a shallow one.")
	
	print("\nLOCAL MODIFICATION MODES:")
	print("  --stash      [Default] Safely stashes local changes and restores them after.")
	print("  --reset      Forcefully wipes out all local changes before updating.")
	print("  --stash-reset STASH FIRST, THEN RESET. Backs up changes, then clears workspace.")
	print("  --reset-stash RESET FIRST, THEN STASH. Clears workspace, then records a stash state.")
	
	print("\nMANUAL REMOTE & BRANCH ARGUMENTS (Optional):")
	print("  You can append a custom remote and branch at the end of 'update' or 'convert'.")
	print("  Format: python git_repo_lite.py <command> <dir> [--mode] [remote] [branch]")
	
	print("\nUSAGE EXAMPLES:")
	print("  👉 Update using auto-detected remote/branch and auto-stash:")
	print("     python git_repo_lite.py update .")
	
	print("\n  👉 Update with hard reset, manually specifying 'origin' and branch 'main':")
	print("     python git_repo_lite.py update . --reset origin main")
	
	print("\n  👉 Convert a repo using a custom remote 'upstream' and branch 'dev':")
	print("     python git_repo_lite.py convert . --stash upstream dev")
	print("=" * 80)

def get_current_branch(repo_dir):
	"""Determines the active local branch name safely."""
	try:
		return run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_dir)
	except Exception:
		return "master"

def get_active_remote(repo_dir):
	"""Dynamically gets the tracking remote name or falls back to 'origin'."""
	try:
		branch = get_current_branch(repo_dir)
		tracking_remote = run_cmd(["git", "config", f"branch.{branch}.remote"], cwd=repo_dir)
		if tracking_remote:
			return tracking_remote
	except Exception:
		pass

	try:
		remotes = run_cmd(["git", "remote"], cwd=repo_dir).splitlines()
		if remotes:
			return remotes[0].strip()
	except Exception:
		pass

	return "origin"

def handle_local_changes(target_dir, mode, action_name):
	"""Manages local modifications before Git operations based on the strict requested order."""
	stashed = False
	
	if mode == "--stash-reset":
		print(f"[{action_name}] Execution Order: STASH -> RESET")
		stash_output = run_cmd(["git", "stash", "push", "-u", "-m", f"Auto-stash backup before Git Repo Lite {action_name}"], cwd=target_dir)
		stashed = "No local changes to save" not in stash_output
		run_cmd(["git", "reset", "--hard", "HEAD"], cwd=target_dir)
		run_cmd(["git", "clean", "-fd"], cwd=target_dir)

	elif mode == "--reset-stash":
		print(f"[{action_name}] Execution Order: RESET -> STASH")
		run_cmd(["git", "reset", "--hard", "HEAD"], cwd=target_dir)
		run_cmd(["git", "clean", "-fd"], cwd=target_dir)
		stash_output = run_cmd(["git", "stash", "push", "-u", "-m", f"Post-reset stash trace for Git Repo Lite {action_name}"], cwd=target_dir)
		stashed = "No local changes to save" not in stash_output

	else:
		if mode == "--stash":
			stash_output = run_cmd(["git", "stash", "push", "-u", "-m", f"Auto-stash before Git Repo Lite {action_name}"], cwd=target_dir)
			stashed = "No local changes to save" not in stash_output
		if mode == "--reset":
			run_cmd(["git", "reset", "--hard", "HEAD"], cwd=target_dir)
			run_cmd(["git", "clean", "-fd"], cwd=target_dir)
		
	return stashed

def clone_repo(repo_url, target_dir):
	"""Performs a size-optimized initial shallow clone."""
	print(f"[Git Repo Lite] Cloning {repo_url} into {target_dir} with minimum size profile...")
	cmd = [
		"git", "clone", 
		"--depth", "1", 
		"--single-branch", 
		"--no-tags", 
		"--recurse-submodules", 
		"--shallow-submodules", 
		repo_url, 
		target_dir
	]
	run_cmd(cmd)
	run_cmd(["git", "gc", "--prune=now"], cwd=target_dir)
	print("[Git Repo Lite] ✨ Success! Shallow clone completed.")

def update_repo(target_dir, mode, manual_remote=None, manual_branch=None):
	"""Updates the repository with dynamic or manual remote and branch configurations."""
	remote = manual_remote if manual_remote else get_active_remote(target_dir)
	branch = manual_branch if manual_branch else get_current_branch(target_dir)
	
	print(f"[Git Repo Lite] Updating repository in {target_dir}")
	print(f"[Git Repo Lite] Target Config -> Remote: '{remote}', Branch: '{branch}', Mode: '{mode}'")
	
	stashed = handle_local_changes(target_dir, mode, "Update")

	try:
		# 1. Fetch specifically from the targeted remote and branch
		run_cmd(["git", "fetch", "--depth", "1", remote, branch], cwd=target_dir)
		
		# 2. Re-verify the target commit string to avoid divergence warnings
		target_ref = f"{remote}/{branch}"
		
		# 3. Apply update strategies
		if mode in ["--reset", "--stash-reset", "--reset-stash"]:
			run_cmd(["git", "reset", "--hard", target_ref], cwd=target_dir)
		else:
			current_local = get_current_branch(target_dir)
			if current_local.lower() != branch.lower():
				print(f"[Git Repo Lite] Switching branch from '{current_local}' to '{branch}'...")
				run_cmd(["git", "checkout", "-B", branch, target_ref], cwd=target_dir)
			else:
				run_cmd(["git", "merge", target_ref, "--ff-only"], cwd=target_dir)
		
		# 4. Sync child submodules
		run_cmd(["git", "submodule", "update", "--init", "--recursive", "--depth", "1"], cwd=target_dir)
		run_cmd(["git", "gc", "--prune=now"], cwd=target_dir)
		
	except Exception as e:
		print(f"[Git Repo Lite] ❌ Error occurred: {e}. Attempting dynamic fallback...")
		run_cmd(["git", "reset", "--hard", "FETCH_HEAD"], cwd=target_dir)
	finally:
		if stashed and mode == "--stash":
			print("[Git Repo Lite] Restoring your local modifications from stash...")
			run_cmd(["git", "stash", "pop"], cwd=target_dir, allow_fail=True)
			
	print("[Git Repo Lite] ✨ Success! Core application and submodules updated safely.")

def convert_existing(target_dir, mode, manual_remote=None, manual_branch=None):
	"""In-place conversion of a deep-history repository with explicit branch targeting."""
	remote = manual_remote if manual_remote else get_active_remote(target_dir)
	branch = manual_branch if manual_branch else get_current_branch(target_dir)
	
	print(f"[Git Repo Lite] Converting deep repository in {target_dir}")
	print(f"[Git Repo Lite] Target Config -> Remote: '{remote}', Branch: '{branch}', Mode: '{mode}'")
	
	run_cmd(["git", "config", f"remote.{remote}.tagOpt", "--no-tags"], cwd=target_dir)
	stashed = handle_local_changes(target_dir, mode, "Conversion")

	try:
		run_cmd(["git", "fetch", "--depth", "1", remote, branch], cwd=target_dir)
		target_ref = f"{remote}/{branch}"
		
		run_cmd(["git", "reset", "--hard", target_ref], cwd=target_dir)
		run_cmd(["git", "submodule", "update", "--init", "--recursive", "--depth", "1"], cwd=target_dir)
		
		run_cmd(["git", "reflog", "expire", "--expire=now", "--all"], cwd=target_dir)
		run_cmd(["git", "gc", "--prune=now", "--aggressive"], cwd=target_dir)
	finally:
		if stashed and mode == "--stash":
			print("[Git Repo Lite] Restoring your local modifications from stash...")
			run_cmd(["git", "stash", "pop"], cwd=target_dir, allow_fail=True)
			
	print("[Git Repo Lite] ✨ Success! Repository converted. Deep history blocks deleted.")

if __name__ == "__main__":
	if len(sys.argv) < 3:
		print_usage()
		sys.exit(1)

	action = sys.argv[1].lower()
	target_path = sys.argv[2]
	
	allowed_modes = ["--stash", "--reset", "--stash-reset", "--reset-stash"]
	mode = "--stash"
	remote_arg = None
	branch_arg = None

	# Secure argument parser execution strategy
	remaining_args = sys.argv[3:]
	if remaining_args:
		if remaining_args[0].lower() in allowed_modes:
			mode = remaining_args[0].lower()
			# If mode matches, remote and branch are shifted down to positions 1 and 2
			if len(remaining_args) >= 2:
				remote_arg = remaining_args[1]
			if len(remaining_args) >= 3:
				branch_arg = remaining_args[2]
		else:
			# If no explicit mode modifier is given, process them directly as remote and branch
			remote_arg = remaining_args[0]
			if len(remaining_args) >= 2:
				branch_arg = remaining_args[1]

	if action == "clone":
		if len(sys.argv) < 4:
			print("[Git Repo Lite] ❌ Error: Target directory is missing!")
			print("Format: python git_repo_lite.py clone ")
			sys.exit(1)
		clone_repo(sys.argv[2], sys.argv[3])
	elif action == "update":
		update_repo(target_path, mode, remote_arg, branch_arg)
	elif action == "convert":
		convert_existing(target_path, mode, remote_arg, branch_arg)
	else:
		print(f"[Git Repo Lite] ❌ Unknown command action: {action}")
		print_usage()
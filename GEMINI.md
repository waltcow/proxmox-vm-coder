# Gemini Project Context

## Project Overview

**Project Name:** Proxmox VM Coder
**Purpose:** A Terraform and Packer template collection for provisioning Linux development workspaces on Proxmox VE, orchestrated by [Coder](https://coder.com/).

This project automates the creation of "Coder Workspaces" — essentially virtual machines on Proxmox that act as remote development environments. It focuses on speed and usability by utilizing cloud-init for initialization and pre-caching heavy assets like VS Code Server.

## Architecture & Technologies

*   **Orchestration:** [Coder](https://coder.com/)
*   **Infrastructure as Code:** Terraform (`main.tf` + modules)
*   **Image Building:** Packer (specifically `packer-next` directory using `proxmox-clone` builder)
*   **Virtualization:** Proxmox VE (utilizing Cloud-Init)
*   **Testing:** Bun (inferred from `bun:test` imports in TypeScript test files)
*   **Scripting:** Bash (for initialization and utility scripts)

## Key Components

### 1. Terraform (`/`)
The root directory contains the main Terraform configuration to be used by Coder.
*   `main.tf`: The entry point. It defines the `coder_agent`, `proxmox_virtual_environment_vm`, and includes sub-modules.
*   `terraform.tfvars`: Configuration for Proxmox credentials and environment-specific settings.

### 2. Modules (`/modules`)
Reusable Terraform modules for specific functionality.
*   `vscode-web` & `vscode-desktop`: Sets up VS Code Server (web or remote). Includes caching logic (`run.sh`) to speed up startup.
*   `git-clone` & `git-config`: Handles git repository setup within the workspace.
*   `agentapi`: A helper module for building AI agent integrations (likely for Coder Tasks). Tests here use `bun:test`.

### 3. Packer (`/packer-next`)
Contains the configuration for building the base VM template.
*   **Goal:** Create a "Golden Image" from a standard Ubuntu Cloud Image.
*   **Advantage:** Reduces workspace startup time from ~15 mins (ISO install) to ~2-5 mins.
*   **Workflow:** Import Cloud Image -> Clone to temp VM -> Provision -> Convert to Template.

## Usage Guide

### Building the Base Image (Packer)
Before using the Terraform template, you must build the Proxmox template.
1.  Navigate to `packer-next/`.
2.  Import the Ubuntu cloud image (see `packer-next/README.md`).
3.  Configure variables in `config.pkrvars.hcl` or `.env`.
4.  Run `packer init .` and `packer build -var-file="config.pkrvars.hcl" .`.

### Deploying the Workspace (Terraform/Coder)
1.  Configure `terraform.tfvars` with your Proxmox API credentials and network settings.
2.  Push the template to Coder:
    ```bash
    coder templates push --yes proxmox-cloudinit --directory .
    ```
3.  Create a workspace via the Coder UI.

## Development & Testing

### Testing
The project appears to use **Bun** for running tests found in the modules (e.g., `modules/agentapi/main.test.ts`).
*   **Command:** Likely `bun test` (requires Bun installed).
*   **Test Logic:** Tests seem to spin up containers or use mocks (`~test` alias) to simulate the environment.

### Conventions
*   **Cloud-Init:** Heavy reliance on `user-data` for bootstrapping the VM.
*   **Caching:** Scripts like `cache-vscode-server.sh` and logic in `vscode-web` module are critical for performance.
*   **Routing:** Custom routing scripts (`route-switch.sh`) are used, possibly for bypassing network restrictions in specific regions.

## File Structure Highlights

*   `main.tf`: Core logic for the Coder template.
*   `modules/`: Functionality split into reusable units.
*   `packer-next/ubuntu-24.04-cloud.pkr.hcl`: The definition for the base VM image.
*   `cloud-init/user-data.tftpl`: The cloud-init configuration injected into the VM.

#!/bin/bash
# Code generation script — produced by CodeMySpec code_generation task
# Re-run on a fresh Phoenix project to reproduce this scaffold.

set -e

# Authentication (LiveView)
mix phx.gen.auth Users User users --live

# Multi-tenant accounts with members and invitations
mix cms_gen.accounts

# OAuth integration scaffolding with encrypted token storage (Cloak vault)
mix cms_gen.integrations

# OAuth providers (one per .code_my_spec/integrations/*.md)
mix cms_gen.integration_provider CodeMySpec codemyspec
mix cms_gen.integration_provider Google google

# CodeMySpec feedback widget with screenshot capture
mix cms_gen.feedback_widget

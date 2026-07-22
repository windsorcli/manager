---
title: Manager
description: Management cluster blueprint layered on top of core.
---

# Manager

Manager is a Windsor blueprint for a management cluster. It layers on top of
[Core](https://github.com/windsorcli/core), which provides the Kubernetes
platform, and adds the control-plane services that operate a fleet of downstream
clusters: self-hosted Omni, the Talos image factory, Harbor, and Cluster API.

The blueprint is built out progressively. See the [README](https://github.com/windsorcli/manager)
for the current state and the target service set.

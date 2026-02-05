# k3s-plex

Plex Media Server deployment for the k3s cluster.

## Overview

This repository deploys Plex Media Server to your k3s cluster using the official Plex helm chart with custom values, following the established GitOps pattern with ArgoCD.

## Deployment Architecture

This deployment uses the official Plex Media Server helm chart with custom configuration:

- **Chart**: `plex-media-server` from https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages
- **Custom Values**: `helm/values.yaml` (version-controlled in this repo)
- **PVCs**: Managed separately in `manifests/` directory (outside helm control)
- **ArgoCD**: Multi-source application combining helm chart + custom values + PVC manifests

### Repository Structure

```
k3s-plex/
├── helm/
│   └── values.yaml          # Custom helm chart configuration
├── manifests/
│   ├── pvc-config.yaml      # 20Gi Longhorn PVC for config
│   └── pvc-transcode.yaml   # 15Gi Longhorn PVC for transcode
├── scripts/
│   └── create-secret.sh     # Plex claim token secret creation
├── Makefile                 # Local development helpers
└── README.md
```

### Auto-Deployment

This repo is deployed automatically by ArgoCD from the `k3s-infra` cluster bootstrap. ArgoCD watches the `helm/` and `manifests/` directories on the `main` branch and automatically syncs changes.

### Prerequisites

- k3s cluster running with ArgoCD installed
- Longhorn storage system deployed and healthy
- Tailscale operator installed and configured
- A node labeled `storage=external` with media directories available
- `plex-claim-token` secret created in `plex` namespace (handled by `k3s-infra`)

### Manual Deployment (Local Development)

For testing before committing to git:

```bash
# Copy environment template
cp .env.example .env

# (Optional) Get claim token from https://www.plex.tv/claim/
# Edit .env and add PLEX_CLAIM_TOKEN (valid for 4 minutes)
vim .env

# Add Plex helm repo and deploy
make deploy  # Installs PVCs, helm chart, and waits for ready

# Check status
make status

# Preview generated manifests
make helm-template
```

## Storage Architecture

### Persistent Volumes (Longhorn)

- **Config/Metadata**: 20GB Longhorn PVC
  - Stores Plex configuration, database, metadata
  - Replicated across nodes (2 replicas)
  - Automatically backed up to MinIO S3

- **Transcode Cache**: 50GB Longhorn PVC
  - Temporary transcoded media files
  - Persistent across pod restarts
  - Can be increased if needed: `kubectl patch pvc plex-transcode -n plex -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'`

### Host Path Mounts

- **TV Shows**: `/mnt/external/tv` → mounted at `/media/tv` (read-only)
- **Movies**: `/mnt/external/movies` → mounted at `/media/movies` (read-only)

Media directories are mounted read-only to prevent accidental deletion or modification.

## Network Access

### Tailscale (Recommended)

Plex is exposed via Tailscale with hostname `plex`:

- **Web UI**: `http://plex.<your-tailnet>.ts.net/web`
- Secure, encrypted access from anywhere on your Tailscale network
- No port forwarding or public exposure required

### Direct Access (LAN)

If you're on the same network as your cluster nodes:

- **Direct IP**: `http://<any-node-ip>/web`
- Note: Service is ClusterIP, so direct access requires being on the cluster network

## Initial Setup

1. **Access Plex Web UI** via Tailscale URL
2. **Sign in** with your Plex account
   - If claim token was configured, server should auto-claim
   - Otherwise, manually claim the server
3. **Complete setup wizard**
4. **Add media libraries**:
   - TV Shows: `/media/tv`
   - Movies: `/media/movies`
5. **Configure settings**:
   - Set preferred quality and bandwidth
   - Enable remote access if desired
   - Configure transcoding settings

## Hardware Acceleration (Optional)

If your cluster nodes have Intel CPUs with QuickSync support:

1. Edit [helm/values.yaml](helm/values.yaml)
2. Uncomment the hardware acceleration sections:
   ```yaml
   pms:
     securityContext:
       privileged: true
   ```
   And in `extraVolumes`:
   ```yaml
   - name: dev-dri
     hostPath:
       path: /dev/dri
       type: Directory
   ```
   And in `extraVolumeMounts`:
   ```yaml
   - name: dev-dri
     mountPath: /dev/dri
   ```
3. Commit and push changes
4. ArgoCD will auto-sync and restart the pod
5. Verify in Plex: Settings → Transcoder → Use hardware acceleration when available

### NVIDIA GPU Support

To enable NVIDIA GPU acceleration, add to [helm/values.yaml](helm/values.yaml):

```yaml
pms:
  gpu:
    nvidia:
      enabled: true
      devices: "all"
      capabilities: "compute,video,utility"
```

## Adding Media

### Option 1: Direct Upload to Host

```bash
# From your workstation
rsync -avh --progress /path/to/movies/ user@control-plane-host:/mnt/external/movies/
rsync -avh --progress /path/to/tv/ user@control-plane-host:/mnt/external/tv/
```

### Option 2: Network Share

Set up an NFS or SMB share on the control-plane host for `/mnt/external/{tv,movies}` directories.

### Auto-Detection

Plex automatically detects new media added to the mounted directories and will scan them during the next library update cycle.

## Backup & Recovery

### Automatic Backups

Plex configuration is stored on Longhorn volumes and automatically backed up to MinIO S3:

- Access Longhorn UI via Tailscale: `http://longhorn.<your-tailnet>.ts.net`
- Navigate to **Volumes** → **plex-config**
- Backups are created automatically based on Longhorn schedule
- Backups stored in MinIO bucket: `longhorn-backups`

### Manual Backup

```bash
# Via Longhorn UI
# 1. Navigate to Volumes → plex-config
# 2. Click "Take Snapshot"
# 3. From snapshot, click "Backup"
```

### Recovery from Backup

```bash
# Via Longhorn UI
# 1. Navigate to Volumes → plex-config
# 2. Click "Create Volume from Backup"
# 3. Select backup and restore
# 4. Restart Plex pod to use restored volume
kubectl rollout restart deployment/plex -n plex
```

### Disaster Recovery

If you need to completely rebuild:

1. Restore `plex-config` volume from Longhorn backup
2. Redeploy Plex via ArgoCD (automatic if repo still exists)
3. Pod will mount restored configuration
4. All settings, libraries, and metadata will be preserved

## Troubleshooting

### Pod Won't Start

```bash
# Check PVC status
kubectl get pvc -n plex

# Check pod events
kubectl describe pod -n plex -l app.kubernetes.io/name=plex-media-server

# Check logs
kubectl logs -n plex -l app.kubernetes.io/name=plex-media-server --tail=100

# Check helm release status
helm list -n plex
helm status plex -n plex
```

**Common issues:**
- PVCs not bound: Verify Longhorn is running
- Node selector mismatch: Verify control-plane node has `storage=external` label
- Media directories missing: SSH to node and check `/mnt/external/{tv,movies}`

### Can't Access via Tailscale

```bash
# Check Tailscale operator
kubectl get pods -n tailscale

# Verify service annotations
kubectl get svc plex -n plex -o yaml | grep tailscale

# Check Tailscale device list
tailscale status | grep plex
```

### Media Libraries Not Visible

```bash
# Verify media mounts inside pod
kubectl exec -n plex statefulset/plex -- ls -la /media/tv /media/movies

# Check directory permissions (should be readable by UID 1000)
# SSH to control-plane node
ls -la /mnt/external/tv /mnt/external/movies
```

Fix permissions if needed:
```bash
sudo chown -R 1000:1000 /mnt/external/tv /mnt/external/movies
sudo chmod -R 755 /mnt/external/tv /mnt/external/movies
```

### Transcoding Fails

```bash
# Check transcode PVC space
kubectl exec -n plex statefulset/plex -- df -h /transcode

# Increase PVC size if full
kubectl patch pvc plex-transcode -n plex -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### Poor Performance

**CPU transcoding is slow:**
- Enable hardware acceleration (see section above)
- Increase CPU limits in deployment.yaml
- Reduce transcoding quality in Plex settings

**Streaming stutters:**
- Check network bandwidth
- Verify transcoding isn't bottlenecked (check `/transcode` PVC space)
- Consider pinning pod to node with better resources

## Maintenance

### Updating Plex

The deployment uses a pinned image version for stability. To update to a new version:

1. Check available versions at https://hub.docker.com/r/plexinc/pms-docker/tags
2. Edit [helm/values.yaml](helm/values.yaml):
   ```yaml
   image:
     tag: "1.43.0.12345-abcdef123"  # Update to desired version
   ```
3. Commit and push changes
4. ArgoCD will auto-sync and restart the pod

To manually force an update:

```bash
# Force pod restart
kubectl rollout restart statefulset/plex -n plex

# Or upgrade helm release locally
make install-helm
```

### Scaling Resources

Edit [helm/values.yaml](helm/values.yaml) and adjust:

```yaml
pms:
  resources:
    requests:
      cpu: "2000m"      # Adjust based on usage
      memory: "4Gi"
    limits:
      cpu: "6000m"
      memory: "12Gi"
```

Commit and push - ArgoCD will auto-sync and restart the pod.

### Monitoring

```bash
# Watch resource usage
kubectl top pod -n plex

# View logs
kubectl logs -n plex -l app.kubernetes.io/name=plex-media-server -f

# Check helm release
helm list -n plex
helm status plex -n plex

# Check ArgoCD sync status
kubectl get application plex -n argocd
```

## Security Considerations

- **Network**: Exposed only via Tailscale (encrypted, ACL-controlled)
- **Storage**: Media mounted read-only to prevent modification
- **User**: Runs as UID 1000 (non-root)
- **Secrets**: Claim token stored in Kubernetes secret (not in git)
- **Allowed Networks**: Restricted to cluster CIDRs

## Makefile Targets

```bash
make help          # Show available targets
make deploy        # Full deployment (secret + PVCs + helm chart)
make create-secret # Create Plex claim token secret
make apply-pvcs    # Apply PVC manifests only
make install-helm  # Install/upgrade helm chart
make helm-template # Preview generated Kubernetes manifests
make status        # Show Plex resources status
make clean         # Remove Plex but keep PVCs
make destroy       # Remove Plex completely (with confirmation)
```

## Customizing Helm Values

All Plex configuration is in [helm/values.yaml](helm/values.yaml). Common customizations:

### Change Timezone
```yaml
extraEnv:
  TZ: "America/New_York"
```

### Adjust Resource Limits
```yaml
pms:
  resources:
    limits:
      cpu: "8000m"
      memory: "16Gi"
```

### Add Additional Media Directories
```yaml
extraVolumes:
  - name: music
    hostPath:
      path: /mnt/external/music
      type: DirectoryOrCreate

extraVolumeMounts:
  - name: music
    mountPath: /media/music
    readOnly: true
```

After making changes, commit and push - ArgoCD will automatically sync.

## License

This configuration is part of the k3s homelab cluster setup.

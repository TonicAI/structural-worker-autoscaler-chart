# tonicai/structural-worker-autoscaler

This chart installs a kubernetes operator that automatically creates structural
workers in response to queued jobs.

## chart values

* `nameOverride`: explicitly set chart name
* `fullnameOverride`: explicitly set the full chart name
* `installation`: configures installation details
* `installation.imagePullSecrets`: a list of image pull secrets to use
* `installation.imagePullSecrets.*.name`: a name of an image pull secret in the namespace
* `installation.imagePullSecrets.*.value`: a base64 `.dockerconfigjson` value, optional. When provided the chart creates this secret
* `installation.crds.installWorkerPool`: boolean, default is true. If false the chart does not install the operator's CRD
* `operator`: options for the operator deployment
* `operator.configuration`: options for the operator
* `operator.configuration.className`: default null. Sets the class name for the operator
* `operator.configuration.defaultClass`: boolean, default true. Sets if the operator is the default for its scope
* `operator.configuration.scope`: Either `namespace` or `cluster`, sets the scope of the operator
* `operator.serviceAccount`: options for the operator's service account
* `operator.serviceAccount.create`: boolean, default true. Controls if the chart creates the operator's service account
* `operator.serviceAccount.name`: explicitly set the service account name
* `operator.serviceAccount.annotations`: key value pair annotations to apply to the service account
* `operator.serviceAccount.labels`: key value pay labels to apply to the service account
* `operator.rbac`: options for the operator's rbac
* `operator.rbac.create`: default true. sets if the chart creates rbac resources
* `operator.rbac.name`: explicitly sets rbac resource names
* `operator.pod.affinity`: sets the affinity property on the operator's pod
* `operator.pod.annotations`: sets the annotations property on the operator's pod
* `operator.pod.labels`: sets the labels property on the operator's pod
* `operator.pod.nodeSelector`: sets the nodeSelector property on the operator's pod
* `operator.pod.securityContext`: sets the securityContext property on the operator's pod
* `operator.pod.tolerations`: sets the tolerations property on the operator's pod
* `operator.pod.volumes`: sets the volumes property on the operator's pod
* `operator.container.env`: a list of k8s `env` definitions
* `operator.container.envFrom`: a list of k8s `envFrom` definitions
* `operator.container.image.repository`: Image repository for the operator image.  Default: quay.io/tonicai/structural-worker-autoscaler
* `operator.container.image.pullPolicy`: Image pull policy for the operator image. Always
* `operator.container.image.tag`: Tag for the operator image. Default: Chart App Version
* `operator.container.resources`: k8s resource definition for the operator container
* `operator.container.securityContext`: k8s container securityContext definition for the operator container
* `operator.container.volumeMounts`: list of k8s volumeMount definitions for the operator container




## Operator

The tonic structural worker pool operator monitors the generation queue of a
structural installation and creates worker pods automatically when jobs are
reported in the queue. The operator enforces a ceiling on the total number of
worker pods it will create for a pool, which is set by `poolCapacity` property.
If the operator finds worker pods in a `Pending` status it assumes none of them
have picked up work from the queue, i.e. the following results in 1 new worker
being created:

- Running: 1
- Pending: 4
- Queue Size: 5
- Current Capacity: 15

The operator does not delete running worker pods unless it is transitioned to
`Shutdown` or the pool resource is deleted. Instead, worker pods created by
this operator have an idle timeout enabled, set by `idleTimeoutMinutes`. Worker
pods will wait at least this long between jobs, after that time period if it
hasn’t picked up work from the queue the worker exits. The operator will
automatically clean up these exited workers at each polling interval. The
operator will also removed errored worker pods during this, but can be
configured to retain these workers by setting `retainFailedWorkers: true`.


### Installation

```bash
helm upgrade --install \
    "oci://quay.io/tonicai/${STRUCTURAL_WORKER_SCALER_CHART}:${STRUCTURAL_WORKER_SCALER_CHART_VERSION}" \
    -n "${STRUCTURAL_WORKER_SCALER_NS}" \
    -f "${VALUES_FILE_PATH}" \
    --wait
```

By default this chart installs a CRD. This can be prevented by setting
`installation.crd.installWorkerPool` to `false`. The operator requires the
CRD to installed but this option allows it to be managed separately.

```bash
helm upgrade --install \
    "oci://quay.io/tonicai/${STRUCTURAL_WORKER_SCALER_CHART}:${STRUCTURAL_WORKER_SCALER_CHART_VERSION}" \
    -n "${STRUCTURAL_WORKER_SCALER_NS}" \
    -f "${VALUES_FILE_PATH}" \
    --set-literal 'installation.crd.installWorkerPool=false' \
    --wait
```

### Configuration

Operator can be restricted to its namespace or it can manage every namespace.
Additionally, multiple operators can be partitioned by setting the same
`className` on both the operator and `StructuralWorkerPool` resources in its
scope. Finally, a single operator in a scope can be the default class and
will process `StructuralWorkerPool` resources without a `className` set. By
default, the operator is installed as the default class in its own namespace.

### Algorithm

At each interval cycle or change to the pool resource, the operator will get
the queue size and total number of created workers for a specific pool. Current
capacity is total capacity minus *all* pods created by the pool, including
failed pods when `retainFailedWorkers: true`

- If there are no jobs in the queue, create 0 workers
- If there’s no capacity, create 0 workers
- If  `queueSize - pendingWorkers <= 0` , create 0 workers
- Otherwise, create `min(capacity, max(0, queueSize - pendingWorkers))` workers


## CRD

After the operator is installed, three resources need to be created in the
same namespace as the structural installation:

1. A `Secret` with a structural api key
2. A `Deployment` for modeling scaled workers
3. A `StructuralWorkerPool` resource

The structural API key requires the "View Analytics" permission.

```yaml
apiVersion: v1
data:
  ApiKey: aGV5IGdldCB5b3VyIG93bgo=
kind: Secret
metadata:
  name: worker-pool-api-key
  namespace: tonic-structural
type: Opaque
```

The worker deployment created by the structural helm chart is recommended for
use with the autoscaler. If you want only autoscaling workers, the replicas on
this source deployment should be set to 0.


```yaml
apiVersion: structural.tonic.ai/v1alpha1
kind: StructuralWorkerPool
metadata:
  name: structural-worker-pool
  namespace: tonic-structural
spec:
  workerPoolClassName: null
  poolCapacity: 30
  queue:
    interval: "00:00:10"
    source:
      # points to structural api server in same namespace
      endpoint: https://tonic-web-server/api/job/peek_queue
      # Secret that contains API key
      secretName: worker-pool-api-key
  status: Active
  workerSpec:
    idleTimeoutMinutes: 3
    # source deployment information
    podTemplate:
      source:
        kind: Deployment
        name: tonic-worker
      # the name of the structural worker container
      # additional configuration is applied to this container by the operator
      containerName: tonic-worker
    retainFailedWorkers: true
status:
  currentCapacity: 30
  failedWorkers: 0
  managedBy: structural-worker-pool
  pendingWorkers: 0
  queueEndpoint: https://tonic-web-server/api/job/peek_queue
  queueSize: 0
  runningWorkers: 0
```

* `spec`: Details this worker pool
    * `spec.workerPoolClassName`: The class name for a worker pool operator. Optional. When not provided the default class operator will manage this resource.
    * `spec.poolCapacity`: Ceiling on number of workers this pool supports. Must be non-negative but may be zero.
        * If this resource is modified to have a lower capacity than the current
        amount of workers the operator treats it this as an at capacity situation.
    * `spec.queue`: Details how the operator retrieves job queue information for this pool.
        * `spec.queue.interval`: How often the operator retrieves job queue information, in `HH:MM:SS` format.
        * `spec.queue.source.endpoint`: The url of the job queue endpoint for this pool
        * `spec.queue.source.secretName`: Name of a `Secret` in the same namespace with the structural api key
    * `spec.status`: Controls this pool's behavior.
        * `Active`: The operator is responding to load on the job queue
        * `Paused`: The operator is not responding to load on the job queue but active workers are left running
        * `Shutdown`: The operator is not responding to load on the job queue but active workers are shutdown and removed
    * `spec.workerSpec`: Details how this pool's workers are managed
        * `spec.workerSpec.idleTimeoutMinutes`: An autoscaled worker is allowed to idle without a job before exiting. The minimum value is 1.
        * `spec.workerSpec.podTemplate.source.name`: The name of a source resource in the same namespace
        * `spec.workerSpec.podTemplate.source.kind`: Defines what kind of resource is the source, only `Deployment` is supported.
        * `spec.workerSpec.podTemplate.containerName`: The name of the structural worker container in the source resource
        * `spec.workerSpec.retainFailedWorkers`: By default the operator will automatically remove worker pods that enter any kind of failed status. This can be set to `true` to disable that behavior.
* `status`: Details the current status of this pool
    * `status.currentCapacity`: How many workers this pool can currently support
    * `status.failedWorkers`: How many worker pods are currently in a `Failed` status
    * `status.managedBy`: The name of the operator managing this worker pool
    * `status.pendingWorkers`: How many worker pods are currently in a `Pending` status
    * `status.queueEndpoint`: The endpoint the operator retrieves queue information from, same as `spec.queue.source.endpoint`
    * `status.queueSize`: How many jobs are available from processing. This is a subset of all jobs are in the `Queued` status.
    * `status.runningWorkers`: How many worker pods are in a `Running` status

### Pod Template

The operator reads a pod template from another resource in the same namespace
as the pool. Currently only `Deployment` is supported. This allows keeping the
pool in sync with a primary worker template with no effort. Updating this
source template does not affect currently running workers.

The operator makes changes to the source pod template, including setting its
restart policy to `Never` , attaching finalizers and owner references, and
using a generated name based on the pool the worker pod belongs to.
Additionally, the operator will attach a label named
`structural.tonic.ai/structural-worker-pool`  and the value will be the name of
the pool the worker pod belongs to. A pool resource named `cloudworkers` will
create worker pods named `cloudworkers-${RANDOM}` and apply
`structural.tonic.ai/structural-worker-pool=cloudworkers` as a label to them.


## Kubectl

Running `kubectl get structuralworkerpools` gives an overview of what the operator believes

- Running Workers: The number of pods that have entered running status
- Pending Workers: Number of pods that aren’t yet running
- Queue Size: How many total generations are in the queue
- Current Capacity: How many more workers can this pool support
    - Failed worker pods kept by `retainFailedWorkers: true` count against the current capacity
- Worker Pool Class Name: What pool class does this belong to, empty means default
- Status: The current status of this pool.
    - Active: Monitoring queue, creating workers
    - Paused: Monitoring queue, not creating workers, existing workers remain
    - Shutdown: Not monitoring queue, not creating workers, existing workers are removed
- Pool Capacity: How many total workers can this pool support
- Interval: How often the generation queue length is checked
- Api Root: URI for queue length API

```
kubectl -n tonic-structural get structuralworkerspools.structural.tonci.ai cloudworkers -o wide
NAME           RUNNINGWORKERS   PENDINGWORKERS   QUEUESIZE   CURRENTCAPACITY   WORKERPOOLCLASSNAME   STATUS     POOLCAPACITY   INTERVAL   APIROOT
cloudworkers   0                0                0           1                                    Shutdown   1              00:01:00   https://tonic-worker.tonic-structural:4433

```

The operator will also attach various events to a pool which can be access by describe

```
kubectl -n tonic-structural describe structuralworkerpools.structural.tonic.ai cloudworkers

Name:         cloudworkers
Namespace:    tonic-structural
Kind:         StructuralWorkerPool
[snip]
Events:
  Type    Reason    Age                   From     Message
  ----    ------    ----                  ----     -------
  Normal  Adopted   9m53s                 prod-us  adopted by prod-us
  Normal  Shutdown  49s (x10 over 9m52s)  prod-us  structural worker pool shutdown

```

Event reasons:

- `Adopted`: An operator has detected this resource and is monitoring its queue
- `FailedToReconcile`: An error occurred during reconciliation, more details can be found in the operator’s logs
- `CleanUp` : The operator has removed 1 or more completed workers
- `FailedWorker`: The operator has detected 1 or more pods in an error status
- `CapacityReached`: The operator has created its allowed amount of workers but more work remains in the queue
- `CreatedWorkers`: The operator has created 1 or more workers
- `Paused`: The pool’s status was changed to `Paused`
- `Shutdown`: The pool’s status was changed to `Shutdown`
- `FailedCleanup`: The operator failed to remove resources when deleting this worker pool
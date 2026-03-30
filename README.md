# Kubernetes Auto-Scaling in Practice - A Complete Walkthrough: HPA, PDB, and Cluster Autoscaler

## Introduction

One of the most powerful capabilities of Kubernetes is its ability to automatically scale workloads up and down in response to real demand — and to scale the underlying infrastructure right alongside them. In this article, we walk through a hands-on demo that covers three pillars of Kubernetes auto-scaling:
-	**Horizontal Pod Autoscaler (HPA)** — scales the number of pods based on CPU utilisation
-	**Pod Disruption Budget (PDB)** — enforces availability constraints during voluntary disruptions
-	**Cluster Autoscaler (CA)** — adds or removes EC2 nodes as pod demand changes
Every step below is backed by real terminal output so you can follow along, reproduce it yourself, or simply understand what is happening under the hood.

## Part 1 — Setting Up the Cluster

**Step 1: Provision the EKS Cluster with Terraform**  
We start by provisioning an Amazon EKS cluster using Terraform. The cluster is configured with a Cluster Autoscaler-enabled Auto Scaling Group (ASG) so that Kubernetes can request new EC2 nodes from AWS when pods cannot be scheduled due to insufficient capacity.

```
terraform init
```

![terraform init](images/01_terraform_init.png)

---

Let's go ahead and provision our kubernetes cluster using Terraform.

```
terraform apply # yes to approve
```

![terraform apply to provision kubernetes cluster](images/02_apply_complete.png)

---


Once Terraform finishes, we update the local kubeconfig and immediately verify the cluster is healthy:

```
aws eks update-kubeconfig --region us-east-1 --name auto_scaler
kubectl get nodes
kubectl top nodes
```

At this point we should have two worker nodes, both Ready, with low resource utilisation. The cluster is empty and waiting for workloads. 

I have also configured the cluster provisioning to install Metrics Server, making it possible to get resource utilization information. This Metrics Server will also enables the HPA to function by providing CPU utilization information.
 
![Two EKS worker nodes are ready and the metrics server](images/03_nodes_and_metrics_active.png)

The Cluster Autoscaler was also installed with Terraform. It watches for pods that cannot be scheduled (Pending state) and asks the ASG to provision new nodes. Without the ASG integration, the Cluster Autoscaler has nowhere to add capacity.

---

**Step 2: Deploy the Application, Service, and HPA**  

Let's navigate into the Kubernetes manifests folder to start our deployments.

```
cd k8s-manifests
```

With the cluster up, we apply three Kubernetes manifests in one go:
-	php-deployment.yaml — a Deployment running the hpa-example image, requesting 480m CPU per pod
-	php-service.yaml — a ClusterIP Service that gives the load generator a stable endpoint
-	php-hpa.yaml — a HorizontalPodAutoscaler targeting 50% average CPU with 2–15 replicas

```
kubectl apply -f php-deployment.yaml
kubectl apply -f php-service.yaml
kubectl apply -f php-hpa.yaml
```

![Deployment, Service, and HPA created successfully](images/04_deploy_depoyment_service_hpa.png)

The HPA manifest is worth examining closely. It uses the autoscaling/v2 API and defines separate scale-up and scale-down behaviors:
- minReplicas: 2
- maxReplicas: 15
- averageUtilization: 50   # target CPU %
- scaleUp:   stabilizationWindowSeconds: 15  # react quickly
           value: 3  pods per 15 s, or 50% of current count
- scaleDown: stabilizationWindowSeconds: 30  # be conservative
           value: 25% of pods per 15 s

The asymmetry is deliberate: I have structured the HPA to scale up the replicas fast to avoid user impact, and scale down slowly to avoid thrashing.
 
---

**Step 3: Confirm the HPA Is Active**
After applying the manifests, we confirm the HPA is reporting correctly:
kubectl get all
We can see the HPA object alongside the Deployment and ReplicaSet. The HPA was set up to scale up the replicas if the CPU utilization gets to 50%. CPU is currently 0%/50%, meaning no load yet. The HPA is idle at 2 replicas (its minimum).
 
![HPA active with 2/2 replicas and 0% CPU utilisation](images/05_hpa_active.png)

**Tip:** Running at least 2 pods provides basic redundancy from the start, and prevents the HPA from scaling all the way down to 1 pod during a quiet period.

---

## Part 2 — Generating Load and Watching HPA Scale Up

**Step 4: Deploy the Load Generator**  

To trigger autoscaling we deploy a load-generator: 2 replicas of a BusyBox container, each running 4 parallel wget loops that hammer the php-apache service as fast as possible.

```
kubectl apply -f load-generator.yaml
```

The load generator application creates 4 worker processes per pod × 2 pods = 8 concurrent HTTP request streams hitting the service continuously. This is enough to push CPU well past the 50% threshold almost immediately. The plan is to emulate increase traffic to our application, leading to higher CPU utilization. Once the CPU utilization goes reaches 50%, the HPA should become active and start scaling the pods to accomodate the increased traffic. 

![Load generator pods are running alongside the php-apache pods](images/06_load_generator_deployed.png)

Once our current nodes get to maximum capacity, they will be unable to accomodate more pods. The waiting pods remain in pending state because there is no space in the cluster to accomodate them. This is where the Cluster Autoscaler comes in. Once the autoscaler notices, the pending pods, it triggers the creation of additional nodes in AWS so that the Pending pods can finally be scheduled in the new cluster nodes. 

**Note:** The Cluster Autoscaler will still respect the min and max node specifications for your node group. 

![eks node group min and max](images/extra_01_eks_node_group_scaling_config.png)

---
  
**Step 5: HPA Detects Overload and Starts Scaling**  

Within seconds of deployoing the load-generator deployment, the HPA metrics server picks up the spike. Because our scaleUp window is only 15 seconds and the policy allows up to 3 new pods every 15 seconds (or 50% of current count, whichever is greater), the HPA reacts quickly.
We can watch the pods in real time:

```
kubectl get pods -l run=php-apache -w
```

The pods are transitioning from Pending → ContainerCreating → Running in rapidly moving the replica count up to 15. 
 
![HPA is active and scaling the application](images/07_scaling_started.png)

---

**Step 6: Cluster Autoscaler Provisions New Nodes**  

The two original nodes only have 2 CPU cores each. With 480m requested per pod, they can host roughly 4 pods each. As the HPA tries to schedule 10–15 pods, many of them land in Pending state because there is no room. This is the signal the Cluster Autoscaler waits for: it detects unschedulable pods and instructs the ASG to launch new EC2 instances. The new nodes join the cluster and go from **Not Ready** to **Ready** to accept new pods.
 
![New nodes joining the cluster](images/08_nodes_scaled_up.png)

```
kubectl get nodes -w
```

We can confirm that new nodes are joining the cluster so they can accomodate the previously pending pods. 

![New instances are provisioned and Ready](images/09_ASG-scaling.png)


# How the Cluster Autoscaler decides:   
In our configuration *php-hpa.yaml*, it checks every 10 seconds. If it sees pods that have been Pending for over 3 minutes due to insufficient resources, it calculates how many new nodes are needed and triggers an ASG scale-out. It will not add more nodes than the ASG maximum stated on the node group configuration.

---

## Part 3 — Removing Load and Watching Scale Down  

**Step 7: Delete the Load Generator - Scaling Down**

Once we have demonstrated scale-out, we remove the load generator to let the system relax:
kubectl delete -f load-generator.yaml
 
Image 10 — 10_delete_load_generator.png: Load generator deployment deleted
Step 8: HPA Begins Scaling Down
Without load, CPU drops to 0%. The HPA does not scale down instantly — it waits for the scaleDown stabilizationWindowSeconds (30 s) and then removes at most 25% of pods every 15 seconds. This prevents flapping if load spikes again briefly.
Watching both pods and HPA simultaneously:
kubectl get pods -l run=php-apache -w
kubectl get hpa -w
 
Image 11 — 11_scale_down_started.png: HPA progressively reducing replica count from 15 back toward 2, with pods Terminating in waves
Step 9: Cluster Autoscaler Scales Down Nodes
Once the pod count drops, nodes have spare capacity. After a cool-down period (default 10 minutes of underutilisation), the Cluster Autoscaler cordons and drains excess nodes and terminates the underlying EC2 instances.
 
Image 12 — 12_nodes_left.png: Cluster returning to fewer nodes as load subsides
 
Image 13 — 13_back_to_2_pods_and_2_nodes.png: System stabilises at 2 pods on 2 nodes — exactly where we started

Part 4 — Manual Scaling and the HPA Relationship
Step 10: Manually Scale the Deployment
One common question is: what happens if you manually scale a deployment that is managed by an HPA? The answer is instructive.
If you scale up beyond the HPA maximum, the HPA will eventually pull it back down. If you scale below the HPA minimum, the HPA will scale it back up. Only within the min/max window does the HPA let your manual change persist — and even then it will adjust it at the next evaluation based on metrics.
kubectl scale deployment php-apache --replicas=3
kubectl get pods -w
 
Image 14 — 14_scale_up_to_3_with_hpa_2.png: Manually scaling to 3 replicas; HPA observes this but does not intervene since 3 is within min=2, max=15
kubectl scale deployment php-apache --replicas=1
 
Image 15 — 15_scale_down_to_1_with_hpa_2.png: Scaling to 1 below the HPA minimum of 2; the HPA immediately restores the second pod
💡 Key takeaway: The HPA owns the replica count. If you manually set replicas below the minimum, the HPA corrects it within the next reconciliation loop (typically within 15–30 seconds). Manual scaling is useful for one-off adjustments but the HPA always has the final say.

Part 5 — Introducing the Pod Disruption Budget
What is a PodDisruptionBudget?
A PodDisruptionBudget (PDB) limits how many pods from a given selector can be voluntarily disrupted at the same time. "Voluntary" means actions like kubectl drain (node maintenance), a rolling deployment update, or the Cluster Autoscaler evicting pods to reclaim a node.
Without a PDB, draining a node could kill all your pods simultaneously if they happened to be running on that node. With a PDB, Kubernetes will refuse an eviction that would violate the budget and retry later.
Step 11: Remove HPA, Apply PDB, and Scale to 5
For this part of the demo, we first delete the HPA (so it does not interfere with our manual replica count) and then create a PDB:
kubectl delete -f php-hpa.yaml
kubectl apply -f php-pdb.yaml
kubectl get pdb
The PDB configuration:
spec:
  minAvailable: 3
  selector:
    matchLabels:
      run: php-apache
This says: at no point during a voluntary disruption may fewer than 3 php-apache pods be available. Since we have 5 pods running and minAvailable is 3, at most 2 can be disrupted simultaneously.
 
Image 16 — 16_pdb_scale_up_to_5.png: HPA deleted, PDB created with minAvailable: 3, deployment scaled to 5
 
Image 17 — 17_pdb_demo_scale_5.png: All 5 pods running, distributed across the two available nodes
Step 12: Drain a Node and Watch the PDB Enforce Its Budget
Now we trigger a voluntary disruption. We cordon one node (preventing new pods from landing on it) and then drain another — which evicts all pods on that node and reschedules them elsewhere.
kubectl cordon ip-10-0-3-92.ec2.internal
kubectl drain ip-10-0-4-159.ec2.internal --ignore-daemonsets --delete-emptydir-data
 
Image 18 — 18_start_drain.png: kubectl drain in progress; the PDB blocks eviction of 75rnw pod with the message "Cannot evict pod as it would violate the pod's disruption budget" and retries after 5s
This is the PDB doing its job. The drain tries to evict all pods on that node at once, but the PDB enforces that 3 must always be available. So evictions happen one at a time, waiting for each evicted pod to be rescheduled and reach Running before allowing the next eviction.
💡 What you would see without a PDB: Without a PDB, all pods on the drained node would be terminated simultaneously. If the application has any in-flight requests or a cold-start delay, this can cause a noticeable outage. The PDB gives Kubernetes the information it needs to perform a rolling eviction instead.
Step 13: Cluster Autoscaler Kicks In During Drain
As pods get evicted from the drained node, they must be rescheduled. But we also cordoned the other original node, so there is no room on the remaining nodes. The Cluster Autoscaler detects the Pending pods and provisions a new node.
 
Image 19 — 19_auto-scaler_kicks_in.png: New node joining the cluster to absorb pods displaced by the drain; kubectl uncordon restores the surviving nodes once the drain completes
Step 14: Extra Nodes Scale Down After Drain Completes
Once the drain is finished and all pods are Running on healthy nodes, the cordoned and drained nodes have no workload. The Cluster Autoscaler marks them for termination and removes them after the cooldown.
 
Image 20 — 20_extra_nodes_scaling_down.png: Excess nodes removed by the Cluster Autoscaler after drain; kubectl get nodes -w shows them moving through SchedulingDisabled → NotReady → gone
Step 15: System Stabilises
After uncordoning the surviving nodes and allowing the Cluster Autoscaler to reclaim the extras, the cluster settles back to a healthy state with all pods distributed across available nodes.
 
Image 21 — 21_system_stable.png: Cluster stable with 5 pods running on 2 nodes after the drain cycle completes

Part 6 — Clean Up
With the demo complete, we clean up all resources to avoid incurring AWS charges:
kubectl delete deployment.apps/php-apache
kubectl delete pdb php-apache-pdb
cd ../terraform-scripts && terraform destroy
 
Image 22 — 22_clean_up.png: Deployment and PDB deleted; 

Use terraform destroy to tear down the EKS cluster and all associated AWS resources.

## Summary: Three Layers of Kubernetes Auto-Scaling

This walkthrough demonstrated how three Kubernetes features work together to create a self-healing, cost-efficient cluster:
Horizontal Pod Autoscaler (HPA)
•	Watches CPU (or custom metrics) against a target utilisation
•	Scales pods up quickly and down conservatively using configurable behaviors
•	Always maintains between minReplicas and maxReplicas
Pod Disruption Budget (PDB)
•	Prevents voluntary disruptions from violating your availability requirements
•	Forces rolling evictions instead of mass terminations during node drain or maintenance
•	Works with the Cluster Autoscaler to protect workloads during scale-down
Cluster Autoscaler (CA)
•	Adds nodes when pods are Pending due to insufficient capacity
•	Removes underutilised nodes after a cooldown period
•	Respects PDBs and pod anti-affinity rules before draining a node

Used together, these three mechanisms mean your application can handle sudden traffic spikes without manual intervention, and your infrastructure costs track actual usage rather than worst-case provisioning.

# EMR on EC2 - External MIT KDC Examples

This project provides sample KDC setups that can be used to achieve different High Availability requirements. See the specific section of each solution to review pros and cons, along with related limits. 

## Usage
1. Launch the script `scripts/setup-artifact-bucket.sh` to copy all the required resources in an S3 bucket that you own. For example: `sh scripts/setup-artifact-bucket.sh YOUR_BUCKET_NAME`. Resources will copied in the a default prefix named `artifacts/aws-emr-external-kdc`.

2. (Optional) Launch the `vpc.yaml` to provision the core VPC infrastructure 

3. Launch one of the KDC template based on your requirements. While launching the stack replace the placeholder `YOUR_BUCKET_NAME` in the __Artifacts Repository__ section with the bucket previosly used and fill all the required parameters. For additional information about each architecture, see next section. 


## Architecture - KDC Solutions

### Architecture 1 - Single KDC - KLMDB - Storage on Amazon EFS

The first solution consists of having a single MIT KDC using Amazon EFS as permanent storage solution. The KDC is behind a Load Balancer with an auto-scaling group set to 1 instance. The MIT KDC is configured to use **KLMDB** as underlying database. In case of failures, clusters are impacted and cannot be launched or scaled (principals cannot be created). In this case also **authN** operations cannot be performed, so no application can be launched on any running cluster. Once the auto-scaling launches a replacement instance, all operations can be resumed without any additional maintenance effort. As alternative to Amazon EFS, it's recommended to use an OpenZFS filesystem. 

#### Pros / Cons

* **P -** Easy to setup. Low management effort. Reduced costs
* **C -** No real HA solution. Can be see an a storage resilient and managed KDC

#### Architecture Type

* Active KDC with Failover

#### Stack Name

- kdc-single-efs.yaml


### Architecture 2 - Single KDC - KLMDB - DB on EBS + Snapshots on Amazon EFS

In this solution, we’re going to install the **KLMBD** database of the KDC on the local EBS storage attached to the instance. As alternative a NVMe based instance can be used for improved performance. When using EBS (GP3), recommended at least (6000 IOPS, better 9000). Having the Database colocated on the KDC instance we can provide optimal performance for kadmind operations, which can fulfill cluster provisioning and scaling of thousands instances with minimal delay. 

To provide fault tolerance, the database is periodically dumped on an attached Amazon EFS volume. The database dump can be performed on a regular basis (recommended not less than 10 sec interval) to avoid losing kerberos principals in case of hardware or Availability Zone issues. In case of a failure, when a new KDC replacement is launched, the new KDC will reload the database from the shared filesystem, and every cluster previously running will be able to resume its operations. 

As in the previous example, if the KDC is terminated, it will not be possible to perform any kind of operation until a new KDC is launched. 

#### Pros / Cons

* Best performance - minimal, if no delay while launching the cluster (this depends on the disk specifications)
* Running clusters will be impacted only for the time an KDC instance is down. Once launched a replacement instance operations can resume normally
* Possible to lose some principals depending on the frequency of the DB snapshots
* Until a new KDC is launched no new operation can be performed (no ticket, no cluster scaling, etc). This can be estimated in 2 minutes (time to launch a new KDC in case of an issue)

#### Architecture Type

* Active KDC with Failover

#### Stack Name

- kdc-single-ebs-efs.yaml


### Highly Available KDC - EFS / ONTAP / OpenZFS Storage

Highly Available architecture that uses a shared filesystem to share the database across multiple KDC instances. In this case a Load Balancer is put in front of the two KDC to route and balance the requests.

#### Pros / Cons

* Can manage up to thousands of nodes with OpenZFS with minimal performance degradation
* No impact in case of a single KDC termination. Clusters can still be launched and users can still authenticate
* Might be expensive depending on the configuration chosen

#### Architecture Type

* Active - Active

#### Stack Name

- kdc-multi-ha.yaml

## Summary

|Solution Type	|Description	|Pros	|Cons	|RTO	|Recommendation	|Notes	|
|---	|---	|---	|---	|---	|---	|---	|
|Local KDC	|	|	|	|	|	|	|
|Local KDC+DB2 (EMR Native)	|No Failover (SPOF)	|Native EMR Solution, no additional effort to maintain. Can use a single EMR Master as external KDC for other clusters.	|Single Point of Failure. For large clusters, is still required to use a GP3 volume on the EMR master node.	|SPOF. Game Over	|For # nodes > 1000 GP3 with 9000 IOPS.	|	|
|	|	|	|	|	|	|	|
|External KDC	|	|	|	|	|	|	|
|Ext. KDC+**KLMDB**+EBS GP3+EFS	|Active - Failover	|Best possible solution in terms of performance. Good balance in terms of performance and data resiliency for the KDC database. Suitable to manage large or multiple clusters	|1. Architecture shift 2. RPO/RTO 3.No real HA.  4. Possible to lose some cluster principals in case of impairments. Depends on the frequency of the snapshots	|ca. 2 minutes	|Best possible solution if managing multiple clusters with thousands of nodes. Minimal degradation with 1k nodes (but you can scale IOPS if you want to have no degradation)	|	|
|Ext. KDC+**DB2**+OpenZFS(Fsx)	|Active - Active	|Same setup as in the blog. OpenZFS recently announced MultiAZ so it can now be used to implement HA solution|1. Cannot use In-memory DB (multi-az)2. Cannot use CFN for creating the Filesystem. Should be available in few weeks the Cloudformation support.	|there shouldn't be any downtime. It's possible to experience some requests failures in case of issues. In catastrofic events, both KDC are terminated,  RTO will be ca. 2 minutes 	|	|No CFN for Multi-AZ (for OpenZFS - requested) 8/17 CFN Integration just released 	|

|# Nodes	|Local KDC - DB2 - Provisioning Time	|Ext. KDC - KLMDB - DB on EBS + Snapshots on Amazon EFS	|Ext. KDC - DB2 + OpenZFS	|Ext. KDC - KLMDB + Amazon EFS (v2)	|
|---	|---	|---	|---	|---	|
|50	|258	|241	|240	|257	|
|100	|293	|228	|262	|293	|
|200	|342	|204	|239	|394	|
|500	|656	|272	|365	|543	|
|1000	|1335	|334	|680	|1008	|


## Sample Script - Populate KDC with EMR principals

Sample script to pre-create principals users requested to launch a cluster. Pre populating the principals cluster might help to support HA configurations is some cases (e.g. No new custom user added, and all principals required to launch a cluster are pre-created on the KDC database). EMR automatically checks if a principal that is going to be created exists on the database. If the user exists, it will generate the keytab for this user requesting a randkey. 

Finally, EMR automatically deletes principals he created when the nodes or the cluster are terminated using EMR shutdown actions. In this case to avoid the delition of the principals on the KDC it will be required to remove Delete permissions for the `kadmin` user. Example ACL policy: 

```bash
echo "kadmin/admin@$KDC_REALM acDeilmps" | sudo tee -a $KDC_PATH/kadm5.acl
```

Below a python example script to pre-populate the KDC based on the VPC CIDR, Kerberos Realm and EMR principals used by frameworks. 

```python
import ipaddress
import subprocess

realm = 'HADOOP.LAN'
domain = 'eu-west-1.compute.internal'
cidr_block = '10.0.0.0/16'
emr_users = ['yarn', 'mapred', 'livy', 'host', 'kms', 'hive', 'hdfs', 'hadoop', 'HTTP', 'spark']

for ip in ipaddress.IPv4Network(cidr_block):
  for user in emr_users: 
    node = str(ip).replace('.','-')
    node_domain = f"ip-{node}.{domain}"
    print(f'create {user} principal for {node_domain}')
    subprocess.run(['kadmin.local', '-q', f"addprinc -randkey {user}/{node_domain}@{realm}"], check=True, text=True)
```


## Sample Metrics

### Size of the KDC Database with 50K principals

51980 principals pre-created. Size of the Database 26MB

```
-rw-r--r--. 1 root root   21 Aug  1 13:18 kadm5.acl
-rw-------. 1 root root 7.5M Aug  1 19:41 principal.lockout.mdb
-rw-------. 1 root root 8.0K Aug  1 19:45 principal.lockout.mdb-lock
-rw-------. 1 root root  26M Aug  1 19:41 principal.mdb
-rw-------. 1 root root 8.0K Aug  1 19:45 principal.mdb-lock
-rw-------. 1 root root   75 Aug  1 13:18 stash
drwxr-xr-x. 2 root root 6.0K Aug  1 13:18 sync
```

## Sample Test Scripts

### Create Test Users
create_users.sh
```bash
#!/bin/bash
realm="HADOOP.LAN"
password="Password123"
num_users=400

for (( i=1; i<=$num_users; i++ )); do
  echo "Creating principal test_user$i@$realm"
  echo -e "$password\n$password\n$password" | kadmin -p kadmin/admin@$realm addprinc "test_user$i@$realm" > /dev/null 2>&1
done
```

### Test Resiliency killing KDC
user_kinit.sh
```bash
#!/bin/sh
realm="HADOOP.LAN"
password="Password123"
num_users="10"

for (( i=1; i<=$num_users; i++ )); do
  echo -e "$password" | kinit test_user$i@$realm > /dev/null 2>&1
  echo $?
done
```

Open the spark shell

```bash
spark-shell --files user_kinit.sh --num-executors 10 --conf spark.dynamicAllocation.enabled=false --conf spark.executor.cores=4
```

Copy the following content

```scala
val tasks = spark.sparkContext.parallelize(1 to 1600, 1600)
val scriptPath = "./user_kinit.sh"
val pipeRDD = tasks.pipe(scriptPath)
pipeRDD.map(_.toInt).sum
```
### Test Read Latency

user_kinit_time.sh
```bash
#!/bin/sh
realm="HADOOP.LAN"
password="Password123"
num_users="100"

for (( i=1; i<=$num_users; i++ )); do
  t1=$(date +%s%3N)
  echo -e "$password" | kinit test_user$i@$realm > /dev/null 2>&1
  t2=$(date +%s%3N)
  echo "$((t2-t1))"
done
```

Open the spark shell

```bash
spark-shell --files user_kinit_time.sh --conf spark.executor.cores=16
```

Copy the following content

```scala
val tasks = spark.sparkContext.parallelize(1 to 800, 800)
val scriptPath = "./user_kinit_time.sh"

// We cache the results of a single test
val pipeRDD = tasks.pipe(scriptPath).cache

// Time is in milliseconds
pipeRDD.map(_.toInt).mean
pipeRDD.map(_.toInt).max
pipeRDD.map(_.toInt).min
```

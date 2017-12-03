# Network VLAN Failover Create

This script create VLANs & Failover Groups in every nodes in the cluster for a ONTAP 8.2

## Getting Started

### Prerequisites

* Data ONTAP 8.2
* NetApp SDK Perl
* The network port or ifgrp must exists in every nodes.
* The network port or ifgrp mustn't be a data role.
* The network port can't have configured an ifgrp on it.
* The network port syntax is 'e/a<number><letter>' where 'e' is used for physical ethernet ports and 'a' for ifgrp, <number> = [0-999], <letter> = is a lowercase letter.
* The VLAN id can't exist in any node.
* The VLAN id & network port must create the same for every nodes.
* The VLAN id must be an integer in the range 1..4094.
* Every nodes have to be healthy. 

### Running

Modify the perl SDK path and Just run the below command

```
./netVlanFGcreate.pl
```
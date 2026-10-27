# ADR-001: NAT gateway strategy

- Status: Accepted
- Date: 2026-10-26
- Deciders: Abdu (Platform Engineer), mentor review

## Context

Our EKS nodes will run in private subnets across two availability zones in `us-east-1`, without public IP addresses. They need outbound access to pull container images, call AWS APIs, and download updates.

We need an approach that balances cost, availability, and maintenance. Monthly estimates below use **hourly price x 730 hours**, without free-tier credits or discounts.

## Options

| Option | Monthly cost (us-east-1, prices as of 2026-10-26) | If it fails | Operational effort |
|---|---|---|---|
| **A. One NAT gateway per AZ** | `2 x $0.045 x 730` = **$65.70**. Two public IPv4 addresses add **$7.30**, making **$73.00/month** before traffic charges. NAT processing: **$0.045/GB**. | If one AZ fails, nodes in the surviving AZ retain outbound access through their local gateway. | Low. AWS manages the gateways; we maintain routes and monitor costs. |
| **B. One shared NAT gateway** | `$0.045 x 730` = **$32.85**. One public IPv4 address adds **$3.65**, making **$36.50/month** before traffic charges. NAT processing: **$0.045/GB**, plus applicable cross-AZ transfer charges. | If the gateway's AZ fails, nodes in both AZs lose the outbound access provided by that gateway. | Low, but recovery requires restoring or replacing the gateway and updating routes. |
| **C. NAT instance - one Linux t4g.nano** | `$0.0042 x 730` = **$3.07** for compute. One public IPv4 address brings this to approximately **$6.72/month**, plus EBS storage and traffic charges. No managed NAT processing fee. | An instance crash or its AZ failing removes outbound access for every subnet using it until recovery. | High. Abdu/platform team must configure NAT, patch the OS, monitor capacity, and handle recovery. |
| **D. VPC endpoints only** | `5 interface endpoints x 2 AZs x $0.01 x 730` = **$73.00/month**, plus **$0.01/GB** processed at the first pricing tier. The S3 gateway endpoint has no endpoint hourly or processing fee. | Endpoints in both AZs avoid relying on one AZ, but failure of a required endpoint or service disrupts that service's access. | Medium. Configure private DNS, security groups, endpoint policies, and all workload dependencies. |

Additional pricing considerations:

- **Shared NAT:** Traffic from the other AZ incurs cross-AZ transfer charges, listed at **$0.01/GB in each direction**, in addition to NAT processing. Internet data transfer charges can also apply to options A, B, and C.
- **NAT instance:** The estimate is a minimum-cost comparison, not proof that a `t4g.nano` can handle our traffic. Sustained CPU usage can also incur surplus CPU credit charges in Unlimited mode.

For option D, the five interface endpoints are:

1. `com.amazonaws.us-east-1.ecr.api`
2. `com.amazonaws.us-east-1.ecr.dkr`
3. `com.amazonaws.us-east-1.sts`
4. `com.amazonaws.us-east-1.ec2`
5. `com.amazonaws.us-east-1.logs`

We would also add the **S3 gateway endpoint** to both private subnet route tables and enable the EKS cluster's private API endpoint. This is the minimum set; features such as EKS Pod Identity or the AWS Load Balancer Controller may require additional endpoints and cost. Public registries, package repositories, and ordinary external APIs remain unreachable unless we provide private alternatives.

## Decision

**Dev:** Choose **B, one shared NAT gateway**, because it provides general outbound access with low maintenance at half the fixed gateway cost of option A; development can tolerate an outbound-access interruption. Add a free S3 gateway endpoint to both private subnet route tables.

**Prod:** Choose **A, one NAT gateway per AZ**, because each AZ keeps its own outbound path and a failure in one AZ does not remove the surviving AZ's egress. Add a free S3 gateway endpoint to both private subnet route tables.

**Budget and lifecycle:** Our total monthly budget is **$30**, so neither environment will run continuously. The dev NAT gateway exists only during working sessions: created with the VPC at session start and destroyed at the end. At about **10 hours per week**, its gateway and public IPv4 charges are roughly **$2 per month**: `10 x 52 / 12 x ($0.045 + $0.005) = $2.17`, before traffic charges and hourly billing rounding. Prod runs only for promotion demos, then is destroyed; its two NAT gateways and two public IPv4 addresses cost **$0.10 per demo hour**, before traffic charges. These are NAT-related costs only; EKS and other resources must also fit within the remaining budget.

## Consequences

- Production has a higher fixed cost, but avoids cross-AZ NAT routing when each private subnet uses its local gateway.
- Development accepts a shared point of failure and cross-AZ transfer charges.
- S3 traffic uses the gateway endpoints instead of the NAT gateways, lowering NAT processing charges.
- A NAT gateway allows outbound traffic to any internet address permitted by the current network rules, so a compromised pod could send data out. Mitigation is planned through Kubernetes network policies and egress controls in Phase 8; NAT alone does not prevent exfiltration.
- NAT instances are cheaper at low usage, but their maintenance and recovery work do not fit our current needs.
- Endpoint-only networking remains an option if we later require strict internet isolation and can supply every dependency privately.
- These estimates cover the egress choices, not the full EKS environment. Revisit the decision when actual traffic and availability requirements are known.

## Questions

- Measure real NAT traffic in Sprint 3, then revisit the cost estimate. Does actual session usage, data processing, and cross-AZ traffic keep the whole environment within the $30 monthly budget?

## Sources

Prices and documentation checked **2026-10-26**:

- [Amazon VPC pricing - NAT gateways and public IPv4 addresses](https://aws.amazon.com/vpc/pricing/)
- [AWS PrivateLink pricing - interface endpoints](https://aws.amazon.com/privatelink/pricing/)
- [Amazon EC2 On-Demand pricing - instances and data transfer](https://aws.amazon.com/ec2/pricing/on-demand/)
- [NAT gateway availability and routing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html)
- [NAT instances and maintenance considerations](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html)
- [Private EKS cluster requirements](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html)

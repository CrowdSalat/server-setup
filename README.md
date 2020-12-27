# Server Setup

## Infrastructure

### VLS

Terraform is used to create a VLS in Hetzner Cloud and a add set of ssh keys to access the VLS. The used module is documented [here](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs), but you may want to consult [normal API doc](https://docs.hetzner.cloud/#overview) because it is more verbose and allows you to get IDs and other crucial stuff. A new API Key can be created in [Hetzner Cloud console](https://console.hetzner.cloud). Make sure to copy it because it is only showed to you once.

```shell
cd infrastructure
terraform init 
terraform apply -var "hcloud_token=YOUR_API_TOKEN"

# to print output
terraform output

# to remove vls
terraform destroy -var "hcloud_token=YOUR_API_TOKEN"
```

### DNS

The DNS is created manually and is configured via [cloudflare webui](https://dash.cloudflare.com/login). There is an A and an AAAA entry configured in cloudflare which map the domain name to the vls ipv4 and ipv6 address. You may need to configure a new CNAME for every subdomain you want to use.

### Domain

The domain weyrich.dev is bought on namecheap (14€ a year) and can be managed via the [webui](https://www.namecheap.com/myaccount/login/?ReturnUrl=%2f). To configure namecheap to use the cloudflare DNS follow the [instructions](https://www.namecheap.com/support/knowledgebase/article.aspx/767/10/how-to-change-dns-for-a-domain/).

## Provisioning

Ansible is used to install on OS.

- docker
- [k3s](https://rancher.com/docs/k3s/latest/en/) 

Ansible is used to install on k3s. 

- drone ci
- [Certbot (Lets Encrypt)]() - to handle certificate renewal
- nginx
  
*I would have used packer to create a ready provisioned os image, but Hetzner only allows standard images for installation.*

## CI/CD

Use drone ci to deploy the following applications in k3s:

- [nginx config]() - as a reverse proxy which handles tls handoff and maps an port to a subdomain (e.g. kvb.weyrich.dev) 
- [kvb]()
- [kvb-ui]()
- [spotidash]()

## Documentation

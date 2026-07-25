provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.oci_region
}

# VCN & Networking
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "k8s-vcn"
  cidr_block     = "10.0.0.0/16"
}

resource "oci_core_internet_gateway" "ig" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "k8s-ig"
  enabled        = true
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "k8s-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ig.id
  }
}

resource "oci_core_security_list" "sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "k8s-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 50000
      max = 50000
    }
  }

  # KubeSpan Wireguard
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 51820
      max = 51820
    }
  }
}

resource "oci_core_subnet" "main_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "k8s-subnet"
  route_table_id    = oci_core_route_table.rt.id
  security_list_ids = [oci_core_security_list.sl.id]
}

resource "local_file" "image_metadata" {
  filename = "${path.module}/image_metadata.json"
  content = jsonencode({
    version = 2
    externalLaunchOptions = {
      firmware                      = "UEFI_64"
      networkType                   = "PARAVIRTUALIZED"
      bootVolumeType                = "PARAVIRTUALIZED"
      remoteDataVolumeType          = "PARAVIRTUALIZED"
      localDataVolumeType           = "PARAVIRTUALIZED"
      launchOptionsSource           = "PARAVIRTUALIZED"
      pvAttachmentVersion           = 2
      pvEncryptionInTransitEnabled  = true
      consistentVolumeNamingEnabled = true
    }
    imageCapabilityData    = null
    imageCapsFormatVersion = null
    operatingSystem        = "Talos"
    operatingSystemVersion = local.talos_version
    additionalMetadata = {
      shapeCompatibilities = [
        {
          internalShapeName = "VM.Standard.A1.Flex"
          ocpuConstraints   = null
          memoryConstraints = null
        }
      ]
    }
  })
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "talos" {
  compartment_id = var.compartment_ocid
  name           = "talos-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "ObjectReadWithoutList"
}

resource "oci_objectstorage_preauthrequest" "upload" {
  access_type  = "AnyObjectWrite"
  bucket       = oci_objectstorage_bucket.talos.name
  name         = "upload-talos"
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  time_expires = timeadd(timestamp(), "2h")
}

resource "null_resource" "upload_talos_oci" {
  triggers = {
    url = local.talos_oci_image
  }
  depends_on = [local_file.image_metadata]
  provisioner "local-exec" {
    command     = "wget -qO- ${local.talos_oci_image} | xz -d > oracle-arm64.raw && qemu-img convert -f raw -O qcow2 oracle-arm64.raw oracle-arm64.qcow2 && tar zcf oracle-arm64.oci oracle-arm64.qcow2 image_metadata.json && curl -s -f -X PUT -T oracle-arm64.oci https://objectstorage.${var.oci_region}.oraclecloud.com${oci_objectstorage_preauthrequest.upload.access_uri}oracle-arm64.oci"
    working_dir = path.module
  }
}

resource "oci_core_image" "talos" {
  compartment_id = var.compartment_ocid
  display_name   = "talos-${replace(local.talos_version, ".", "-")}-${substr(local.talos_schematic_id, 0, 7)}"
  depends_on     = [null_resource.upload_talos_oci]

  image_source_details {
    source_type              = "objectStorageTuple"
    bucket_name              = oci_objectstorage_bucket.talos.name
    namespace_name           = data.oci_objectstorage_namespace.ns.namespace
    object_name              = "oracle-arm64.oci"
    operating_system         = "Custom"
    operating_system_version = "Custom"
  }
}

# Availability Domain (Always Free requires a specific AD)
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Compute Instance
resource "oci_core_instance" "talos_oci" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "talos-cp-oci"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type             = "image"
    source_id               = oci_core_image.talos.id
    boot_volume_size_in_gbs = 50 # Free tier limit is 200GB.
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main_subnet.id
    assign_public_ip = true
  }
}

output "oci_public_ip" {
  value = oci_core_instance.talos_oci.public_ip
}

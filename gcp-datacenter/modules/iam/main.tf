locals {
  # Llave estable por asignación: la explícita si se dio; si no, los cuatro campos. Debe
  # conocerse en el plan (por eso existe key, para miembros o recursos calculados).
  bindings = {
    for b in var.bindings :
    (b.key != null ? b.key : join("|", [b.scope, b.resource, b.role, b.member])) => b
  }

  by_scope = {
    for s in [
      "organization", "project", "service_account", "storage_bucket", "kms_key_ring",
      "kms_crypto_key", "secret", "subnetwork",
    ] : s => { for k, b in local.bindings : k => b if b.scope == s }
  }
}

# Solo recursos *_iam_member: cada uno agrega un miembro a un rol y no toca a los demás
# miembros del recurso (nunca *_iam_binding ni *_iam_policy, que son autoritativos).

resource "google_organization_iam_member" "this" {
  for_each = local.by_scope["organization"]

  org_id = trimprefix(each.value.resource, "organizations/")
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_project_iam_member" "this" {
  for_each = local.by_scope["project"]

  project = each.value.resource
  role    = each.value.role
  member  = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_service_account_iam_member" "this" {
  for_each = local.by_scope["service_account"]

  service_account_id = each.value.resource
  role               = each.value.role
  member             = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_storage_bucket_iam_member" "this" {
  for_each = local.by_scope["storage_bucket"]

  bucket = each.value.resource
  role   = each.value.role
  member = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_kms_key_ring_iam_member" "this" {
  for_each = local.by_scope["kms_key_ring"]

  key_ring_id = each.value.resource
  role        = each.value.role
  member      = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_kms_crypto_key_iam_member" "this" {
  for_each = local.by_scope["kms_crypto_key"]

  crypto_key_id = each.value.resource
  role          = each.value.role
  member        = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_secret_manager_secret_iam_member" "this" {
  for_each = local.by_scope["secret"]

  # El ID completo projects/<p>/secrets/<s> identifica el proyecto; no hace falta "project".
  secret_id = each.value.resource
  role      = each.value.role
  member    = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_compute_subnetwork_iam_member" "this" {
  for_each = local.by_scope["subnetwork"]

  # resource = projects/<p>/regions/<r>/subnetworks/<s>; se separa en sus partes.
  project    = split("/", each.value.resource)[1]
  region     = split("/", each.value.resource)[3]
  subnetwork = split("/", each.value.resource)[5]
  role       = each.value.role
  member     = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

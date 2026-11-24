# Prueba de la raíz 0-bootstrap sin GCP: mock_provider y command = plan. Los valores calculados
# que los módulos validan por formato (llave KMS, correos de cuentas de servicio) tienen valores
# simulados con el formato real.

mock_provider "google" {
  # Los valores simulados se usan ya en el plan (Terraform >= 1.11): así se comprueban el
  # principalSet exacto, la llave del bucket, la etiqueta y el principal de la denegación.
  override_during = plan

  mock_data "google_project" {
    defaults = {
      number = "222222222222"
    }
  }
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-222222222222@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_kms_key_ring" {
    defaults = {
      id = "projects/example-project-id/locations/us/keyRings/bnt-bootstrap-sec-keyring-us"
    }
  }
  mock_resource "google_kms_crypto_key" {
    defaults = {
      id = "projects/example-project-id/locations/us/keyRings/bnt-bootstrap-sec-keyring-us/cryptoKeys/bnt-bootstrap-sec-state"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email     = "bnt-tf-stage@example-project-id.iam.gserviceaccount.com"
      member    = "serviceAccount:bnt-tf-stage@example-project-id.iam.gserviceaccount.com"
      name      = "projects/example-project-id/serviceAccounts/bnt-tf-stage@example-project-id.iam.gserviceaccount.com"
      unique_id = "100000000000000000001"
    }
  }
  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool"
    }
  }
  mock_resource "google_iam_workload_identity_pool_provider" {
    defaults = {
      name = "projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/providers/bnt-bootstrap-sec-github"
    }
  }
  mock_resource "google_tags_tag_key" {
    defaults = {
      id              = "tagKeys/333333333333"
      namespaced_name = "example-project-id/bnt-proteccion"
    }
  }
  mock_resource "google_tags_tag_value" {
    defaults = {
      id = "tagValues/444444444444"
    }
  }
}

mock_provider "google-beta" {}

# Mismos valores que terraform.tfvars.example, salvo los IDs de GitHub: aquí son distintos
# entre sí para que la prueba distinga el ID del repositorio del de su dueño.
variables {
  project_id                 = "example-project-id"
  billing_account            = "000000-000000-000000"
  prefix                     = "bnt"
  primary_region             = "us-central1"
  dr_region                  = "us-east4"
  github_repository          = "example-org/example-repo"
  github_repository_id       = "100000001"
  github_repository_owner_id = "200000002"
  state_bucket_location      = "US"
  budget_amount              = 300
  labels = {
    app         = "landing-zone"
    owner       = "plataforma"
    cost_center = "ti-001"
  }
}

run "plan_con_valores_de_ejemplo" {
  command = plan

  # --- Proyecto, APIs y valores únicos (ADR 0029 §2 y §4) ---
  assert {
    condition     = output.project_id == "example-project-id" && output.project_number == "222222222222"
    error_message = "project_id y project_number deben salir del proyecto dado."
  }
  assert {
    condition = alltrue([for a in [
      "cloudresourcemanager.googleapis.com", "iam.googleapis.com", "sts.googleapis.com", "cloudkms.googleapis.com",
      "storage.googleapis.com", "compute.googleapis.com", "dns.googleapis.com", "servicenetworking.googleapis.com",
      "networkmanagement.googleapis.com", "secretmanager.googleapis.com", "container.googleapis.com",
      "sqladmin.googleapis.com", "cloudasset.googleapis.com", "essentialcontacts.googleapis.com",
      "billingbudgets.googleapis.com", "cloudscheduler.googleapis.com", "binaryauthorization.googleapis.com",
    ] : contains(keys(google_project_service.this), a)])
    error_message = "Faltan APIs del proyecto (todas viven aquí, una sola vez)."
  }
  assert {
    condition     = alltrue([for s in google_project_service.this : s.disable_on_destroy == false && s.project == "example-project-id"])
    error_message = "Ninguna API se apaga al destruir (ADR 0029 §2)."
  }
  assert {
    condition     = toset(keys(google_project_service_identity.this)) == toset(["artifactregistry.googleapis.com", "file.googleapis.com", "gkebackup.googleapis.com", "pubsub.googleapis.com", "redis.googleapis.com", "secretmanager.googleapis.com", "sqladmin.googleapis.com"])
    error_message = "Los agentes de servicio que 1-base usa se crean aquí."
  }
  assert {
    condition     = google_compute_project_metadata_item.os_login.key == "enable-oslogin" && google_compute_project_metadata_item.os_login.value == "TRUE"
    error_message = "OS Login debe quedar activo en el proyecto (CIS 4.4)."
  }
  assert {
    condition     = google_project_default_service_accounts.this.action == "DEPRIVILEGE"
    error_message = "La cuenta de Compute por defecto debe quedar sin roles/editor."
  }
  assert {
    condition = alltrue([
      google_billing_budget.project.budget_filter[0].projects == toset(["projects/222222222222"]),
      google_billing_budget.project.display_name == "bnt-bootstrap-ops-budget",
      google_billing_budget.project.amount[0].specified_amount[0].units == "300",
    ])
    error_message = "El presupuesto va filtrado al proyecto único."
  }

  # --- Estado (§6.1) ---
  assert {
    condition     = output.state_bucket == "bnt-bootstrap-ops-tfstate"
    error_message = "El bucket de estado debe llamarse <prefix>-bootstrap-ops-tfstate."
  }
  assert {
    condition = alltrue([
      google_storage_bucket.state.project == "example-project-id",
      google_storage_bucket.state.versioning[0].enabled,
      google_storage_bucket.state.uniform_bucket_level_access,
      google_storage_bucket.state.public_access_prevention == "enforced",
      google_storage_bucket.state.force_destroy == false,
      google_storage_bucket.state.encryption[0].default_kms_key_name == module.state_kms.key_ids["state"],
      google_storage_bucket.state.location == "US",
      module.state_kms.location == "us",
      module.state_kms.keyring_name == "bnt-bootstrap-sec-keyring-us",
    ])
    error_message = "El bucket de estado debe ser versionado, uniforme, sin acceso público, multirregional y con su llave en us."
  }
  assert {
    condition     = google_kms_crypto_key_iam_member.state_storage_agent.member == "serviceAccount:service-222222222222@gs-project-accounts.iam.gserviceaccount.com"
    error_message = "El agente de Cloud Storage debe poder usar la llave del estado."
  }

  # --- Cuentas del pipeline (ADR 0029 §3) ---
  assert {
    condition = toset(keys(output.stage_service_accounts)) == toset([
      "1-base", "2-networks", "2-networks/dev", "2-networks/qa", "2-networks/prod",
      "3-workloads/dev", "3-workloads/qa", "3-workloads/prod",
    ])
    error_message = "stage_service_accounts debe tener exactamente las ocho raíces del ADR 0029."
  }
  assert {
    condition = alltrue([
      google_service_account.stage["1-base"].account_id == "bnt-tf-base",
      google_service_account.stage["2-networks"].account_id == "bnt-tf-net",
      google_service_account.stage["2-networks/qa"].account_id == "bnt-tf-net-qa",
      google_service_account.stage["3-workloads/prod"].account_id == "bnt-tf-wl-prod",
      google_service_account.read.account_id == "bnt-tf-read",
      output.read_service_account == google_service_account.read.email,
    ])
    error_message = "Las cuentas deben llamarse <prefix>-tf-base, -tf-net, -tf-net-<env>, -tf-wl-<env> y -tf-read."
  }

  # Mínimo privilegio: sin roles básicos, sin serviceAccountAdmin, sin storage.admin ni
  # projectIamAdmin sin condición (ADR 0029 §3 y §5).
  assert {
    condition = alltrue([for k, b in module.stage_iam.bindings :
      !contains(["roles/owner", "roles/editor", "roles/iam.serviceAccountAdmin", "roles/iam.roleAdmin", "roles/iam.securityAdmin", "roles/serviceusage.serviceUsageAdmin"], b.role)
    ])
    error_message = "Ninguna cuenta del pipeline recibe roles básicos, serviceAccountAdmin, roleAdmin, securityAdmin ni serviceUsageAdmin."
  }
  assert {
    condition = alltrue([for k, b in module.stage_iam.bindings :
      module.stage_iam.conditions[k] != null if contains(["roles/storage.admin", "roles/resourcemanager.projectIamAdmin", "roles/cloudkms.admin"], b.role)
    ])
    error_message = "storage.admin, projectIamAdmin y cloudkms.admin siempre van condicionados."
  }
  assert {
    condition = alltrue([
      module.stage_iam.conditions["project|3-workloads/dev|roles/storage.admin"].expression == "resource.name.startsWith(\"projects/_/buckets/bnt-dev-\")",
      module.stage_iam.conditions["project|3-workloads/prod|roles/storage.admin"].expression == "resource.name.startsWith(\"projects/_/buckets/bnt-prod-\")",
      module.stage_iam.conditions["project|1-base|roles/storage.admin"].expression == "resource.name.startsWith(\"projects/_/buckets/bnt-common-\")",
    ])
    error_message = "storage.admin se condiciona al prefijo de buckets del entorno (common para 1-base)."
  }
  assert {
    condition     = module.stage_iam.conditions["project|1-base|roles/cloudkms.admin"].expression == "!resource.name.startsWith(\"projects/example-project-id/locations/us/keyRings/bnt-bootstrap-\")"
    error_message = "cloudkms.admin de 1-base excluye el llavero del estado."
  }
  # Concesión delegada de 1-base: dos asignaciones, una por lista, cada una con 10 roles como
  # máximo (límite de hasOnly en la documentación de IAM).
  assert {
    condition = alltrue([
      for k in ["personas", "ejecucion"] : startswith(
        module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|${k}"].expression,
        "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(["
      )
    ])
    error_message = "projectIamAdmin de 1-base es una concesión delegada en dos asignaciones (personas y ejecución)."
  }
  assert {
    condition = alltrue([
      length(local.base_grantable_roles) <= 10,
      length(local.runtime_grantable_roles) <= 10,
      strcontains(module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|ejecucion"].expression, "'roles/cloudsql.instanceUser'"),
      strcontains(module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|ejecucion"].expression, "'projects/example-project-id/roles/bntOffHoursScheduler'"),
      !strcontains(module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|ejecucion"].expression, "'roles/viewer'"),
      strcontains(module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|personas"].expression, "'roles/viewer'"),
      !strcontains(module.stage_iam.conditions["project|1-base|roles/resourcemanager.projectIamAdmin|personas"].expression, "'roles/cloudsql.client'"),
    ])
    error_message = "Cada lista de la concesión delegada tiene sus roles y no más de 10."
  }
  # Hallazgos 2 y 4: las cuentas de los entornos no administran cuentas de servicio ni IAM de
  # proyecto; las cuentas de ejecución y sus roles son de 1-base.
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "qa", "prod"] : [
        for r in ["roles/resourcemanager.projectIamAdmin", "roles/iam.serviceAccountUser", "projects/example-project-id/roles/bntTfServiceAccountManager"] :
        !contains(keys(module.stage_iam.bindings), "project|3-workloads/${e}|${r}")
      ]
    ]))
    error_message = "tf-wl-<env> no tiene projectIamAdmin, serviceAccountUser de proyecto ni el rol de cuentas de servicio."
  }
  assert {
    condition     = length([for k, b in module.stage_iam.bindings : k if b.role == "roles/resourcemanager.projectIamAdmin" && !startswith(k, "project|1-base|")]) == 0
    error_message = "Solo 1-base tiene la concesión delegada de projectIamAdmin."
  }
  assert {
    condition = alltrue([
      contains(keys(module.stage_iam.bindings), "project|3-workloads/dev|roles/cloudscheduler.admin"),
      contains(keys(module.stage_iam.bindings), "project|3-workloads/qa|roles/cloudscheduler.admin"),
      !contains(keys(module.stage_iam.bindings), "project|3-workloads/prod|roles/cloudscheduler.admin"),
      contains(keys(module.stage_iam.bindings), "project|1-base|projects/example-project-id/roles/bntTfServiceAccountManager"),
    ])
    error_message = "cloudscheduler.admin solo en dev y qa (ADR 0028); el rol de cuentas de servicio, solo en 1-base."
  }
  assert {
    condition = alltrue([
      contains(keys(module.stage_iam.bindings), "project|2-networks/dev|projects/example-project-id/roles/bntTfNetworkTagManager"),
      contains(keys(module.stage_iam.bindings), "project|2-networks/dev|roles/servicenetworking.networksAdmin"),
      !contains(keys(module.stage_iam.bindings), "project|2-networks|projects/example-project-id/roles/bntTfNetworkTagManager"),
      contains(keys(module.stage_iam.bindings), "project|2-networks|roles/dns.admin"),
    ])
    error_message = "El rol de etiquetas y servicenetworking solo para los spokes; el hub tiene red, seguridad y DNS."
  }
  # Los agentes de GKE y de las APIs de Google reciben tagUser aquí (lo aplica una persona), no en
  # 1-base: la concesión delegada de 1-base no incluye tagUser.
  assert {
    condition = alltrue([
      google_project_iam_member.tag_user_agents["gke"].member == "serviceAccount:service-222222222222@container-engine-robot.iam.gserviceaccount.com",
      google_project_iam_member.tag_user_agents["apis"].member == "serviceAccount:222222222222@cloudservices.gserviceaccount.com",
      google_project_iam_member.tag_user_agents["apis"].role == "roles/resourcemanager.tagUser",
      !contains(local.base_grantable_roles, "roles/resourcemanager.tagUser"),
    ])
    error_message = "tagUser de proyecto solo para los dos agentes de Google, desde 0-bootstrap."
  }
  assert {
    condition = alltrue([for r in ["roles/viewer", "roles/iam.securityReviewer", "roles/cloudasset.viewer", "roles/networkmanagement.admin"] :
      module.stage_iam.bindings["project|read|${r}"].member == google_service_account.read.member
    ])
    error_message = "tf-read recibe viewer, securityReviewer, cloudasset.viewer y networkmanagement.admin."
  }
  assert {
    condition = alltrue([
      length(module.org_policies) == 0,
      length(module.vpc_sc) == 0,
      output.org_policies_enabled == false,
      output.vpc_sc_perimeter_name == null,
      length([for b in values(module.stage_iam.bindings) : b if b.scope == "organization"]) == 0,
    ])
    error_message = "Sin org_id no hay políticas de organización, perímetro ni roles de organización."
  }

  # --- Estado por raíz (ADR 0029 §3) ---
  assert {
    condition = alltrue([
      output.state_iam_conditions["1-base"].reads == ["0-bootstrap"],
      output.state_iam_conditions["2-networks"].writes == ["2-networks/hub"],
      output.state_iam_conditions["2-networks"].reads == [],
      output.state_iam_conditions["2-networks/qa"].reads == ["2-networks/hub"],
      output.state_iam_conditions["3-workloads/prod"].writes == ["3-workloads/prod"],
      output.state_iam_conditions["3-workloads/prod"].reads == ["1-base", "2-networks/prod"],
    ])
    error_message = "La tabla de estado no coincide con el ADR 0029 (las raíces de red no leen 1-base)."
  }
  assert {
    condition = module.stage_iam.conditions["state|3-workloads/dev|roles/storage.objectViewer"].expression == join(" || ", [
      "resource.type == \"storage.googleapis.com/Bucket\"",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/1-base/\")",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/2-networks/dev/\")",
    ])
    error_message = "3-workloads/dev lee solo 1-base y 2-networks/dev."
  }
  assert {
    condition = module.stage_iam.conditions["state|2-networks|roles/storage.objectAdmin"].expression == join(" || ", [
      "resource.type == \"storage.googleapis.com/Bucket\"",
      "resource.name.startsWith(\"projects/_/buckets/bnt-bootstrap-ops-tfstate/objects/2-networks/hub/\")",
    ])
    error_message = "El hub escribe solo 2-networks/hub/ (la barra final evita prefijos hermanos)."
  }
  assert {
    condition     = !contains(keys(module.stage_iam.bindings), "state|2-networks|roles/storage.objectViewer")
    error_message = "El hub no lee ningún otro estado."
  }
  assert {
    condition     = module.stage_iam.bindings["state|read|roles/storage.objectViewer"].resource == "bnt-bootstrap-ops-tfstate" && module.stage_iam.conditions["state|read|roles/storage.objectViewer"] == null
    error_message = "tf-read lee todo el bucket de estado."
  }

  # --- WIF (ADR 0029 §3) ---
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_id == \"100000001\" && assertion.repository_owner_id == \"200000002\""
    error_message = "attribute_condition debe exigir los IDs numéricos del repositorio y de su dueño."
  }
  assert {
    condition = alltrue([
      module.stage_iam.bindings["wif|1-base|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.deploy/common",
      module.stage_iam.bindings["wif|2-networks|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.deploy/common",
      module.stage_iam.bindings["wif|2-networks/dev|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.deploy/dev",
      module.stage_iam.bindings["wif|3-workloads/prod|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.deploy/prod",
      module.stage_iam.bindings["wif|read|roles/iam.workloadIdentityUser"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/bnt-bootstrap-sec-wif-pool/attribute.repository_id/100000001",
    ])
    error_message = "1-base y el hub solo con attribute.deploy common, cada cuenta de entorno con el suyo y tf-read con todo el repositorio."
  }
  assert {
    condition = alltrue([
      for k, b in module.stage_iam.bindings :
      strcontains(b.member, "/attribute.deploy/") if b.role == "roles/iam.workloadIdentityUser" && k != "wif|read|roles/iam.workloadIdentityUser"
    ])
    error_message = "Toda cuenta que escribe se liga a attribute.deploy (main, flujo del repositorio y entorno), nunca a attribute.environment."
  }
  assert {
    condition = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.deploy"] == join(" ", [
      "('environment' in assertion",
      "&& assertion.ref == 'refs/heads/main'",
      "&& 'job_workflow_ref' in assertion",
      "&& assertion.job_workflow_ref.startsWith('example-org/example-repo/.github/workflows/'))",
      "? assertion.environment : 'none'",
    ])
    error_message = "attribute.deploy exige main, un flujo de .github/workflows/ de este repositorio y un entorno; si no, 'none'."
  }
  assert {
    condition = alltrue([
      google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.environment"] == "'environment' in assertion ? assertion.environment : 'none'",
      length(google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.deploy"]) <= 2048,
    ])
    error_message = "Las afirmaciones opcionales se leen solo si están, y cada expresión cabe en 2048 caracteres."
  }

  # --- Roles personalizados ---
  assert {
    condition = output.custom_role_ids == {
      secret_container_admin  = "projects/example-project-id/roles/bntTfSecretContainerAdmin"
      service_account_manager = "projects/example-project-id/roles/bntTfServiceAccountManager"
      network_tag_manager     = "projects/example-project-id/roles/bntTfNetworkTagManager"
      off_hours_scheduler     = "projects/example-project-id/roles/bntOffHoursScheduler"
    }
    error_message = "custom_role_ids debe dar el ID completo de los roles personalizados."
  }
  assert {
    condition = alltrue([
      length([for p in google_project_iam_custom_role.this["secret_container_admin"].permissions : p if startswith(p, "secretmanager.versions.")]) == 0,
      contains(google_project_iam_custom_role.this["secret_container_admin"].permissions, "secretmanager.secrets.setIamPolicy"),
      length([for p in google_project_iam_custom_role.this["service_account_manager"].permissions : p if strcontains(p, "TagBinding")]) == 0,
      contains(google_project_iam_custom_role.this["service_account_manager"].permissions, "iam.serviceAccounts.setIamPolicy"),
    ])
    error_message = "Contenedores de secretos con su IAM y sin versiones; cuentas de servicio sin permisos de etiquetas."
  }

  # --- Protección (ADR 0029 §5) ---
  assert {
    condition = alltrue([
      google_tags_tag_key.protection["this"].parent == "projects/example-project-id",
      google_tags_tag_key.protection["this"].short_name == "bnt-proteccion",
      google_tags_tag_value.stage0["this"].short_name == "etapa-0",
      google_tags_location_tag_binding.state_bucket["this"].parent == "//storage.googleapis.com/projects/_/buckets/bnt-bootstrap-ops-tfstate",
      google_tags_location_tag_binding.state_bucket["this"].location == "us",
      google_tags_location_tag_binding.state_keyring["this"].parent == "//cloudkms.googleapis.com/projects/example-project-id/locations/us/keyRings/bnt-bootstrap-sec-keyring-us",
      length(google_tags_tag_binding.pipeline_accounts) == 9,
      google_tags_tag_binding.pipeline_accounts["read"].parent == "//iam.googleapis.com/projects/example-project-id/serviceAccounts/100000000000000000001",
    ])
    error_message = "La etiqueta etapa-0 se liga al bucket, al llavero del estado y a las nueve cuentas."
  }
  assert {
    condition = alltrue([
      google_iam_deny_policy.pipeline["this"].parent == "cloudresourcemanager.googleapis.com%2Fprojects%2Fexample-project-id",
      google_iam_deny_policy.pipeline["this"].name == "bnt-bootstrap-sec-deny-pipeline",
      length(google_iam_deny_policy.pipeline["this"].rules) == 3,
      length(google_iam_deny_policy.pipeline["this"].rules[0].deny_rule[0].denied_principals) == 9,
      google_iam_deny_policy.pipeline["this"].rules[0].deny_rule[0].denial_condition[0].expression == "resource.matchTag('example-project-id/bnt-proteccion', 'etapa-0')",
      length(google_iam_deny_policy.pipeline["this"].rules[1].deny_rule[0].denial_condition) == 0,
    ])
    error_message = "La denegación va en el proyecto, contra las nueve cuentas, con una regla por etiqueta y otra sin condición."
  }
  # Valores de secretos: negados a las cuentas del pipeline salvo tf-net (VPN real del hub).
  # El simulado da el mismo correo a todas las cuentas, así que se cuentan los principales.
  assert {
    condition = alltrue([
      google_iam_deny_policy.pipeline["this"].rules[2].deny_rule[0].denied_permissions == tolist(["secretmanager.googleapis.com/versions.access"]),
      length(google_iam_deny_policy.pipeline["this"].rules[2].deny_rule[0].denied_principals) == 8,
      length(google_iam_deny_policy.pipeline["this"].rules[2].deny_rule[0].denial_condition) == 0,
    ])
    error_message = "secretmanager.versions.access se niega a ocho de las nueve cuentas (todas menos tf-net)."
  }
  assert {
    condition = alltrue(concat(
      [for p in ["storage.googleapis.com/buckets.delete", "storage.googleapis.com/buckets.setIamPolicy", "iam.googleapis.com/serviceAccounts.actAs", "iam.googleapis.com/serviceAccounts.getAccessToken", "iam.googleapis.com/serviceAccounts.setIamPolicy", "cloudkms.googleapis.com/cryptoKeyVersions.destroy"] :
      contains(google_iam_deny_policy.pipeline["this"].rules[0].deny_rule[0].denied_permissions, p)],
      [for p in ["iam.googleapis.com/workloadIdentityPoolProviders.update", "iam.googleapis.com/roles.update", "iam.googleapis.com/serviceAccountKeys.create"] :
      contains(google_iam_deny_policy.pipeline["this"].rules[1].deny_rule[0].denied_permissions, p)],
    ))
    error_message = "Se niega cambiar o borrar el bucket, suplantar o cambiar el IAM de las cuentas, el proveedor de WIF y los roles personalizados."
  }
  assert {
    # Lo que las cuentas sí hacen: objetos de su estado, cuota del proyecto e IAM delegado.
    condition = alltrue([for r in google_iam_deny_policy.pipeline["this"].rules : alltrue([for p in r.deny_rule[0].denied_permissions :
      (!startswith(p, "storage.googleapis.com/objects.") || p == "storage.googleapis.com/objects.setIamPolicy") &&
      !startswith(p, "serviceusage.googleapis.com/") &&
      p != "cloudresourcemanager.googleapis.com/projects.setIamPolicy"
    ])])
    error_message = "La denegación no puede quitar los objetos del estado, el proyecto de cuota ni el IAM delegado."
  }
}

# Hallazgo 1: quitar la etiqueta <prefix>-proteccion de un recurso exige
# resourcemanager.tagValueBindings.delete sobre el valor y <recurso>.deleteTagBinding sobre el
# recurso (guía de etiquetas de Resource Manager). Se revisan TODOS los roles de proyecto y de
# organización de las nueve cuentas. Roles predefinidos que traen alguno de esos permisos o el IAM
# de las etiquetas, según la referencia de roles (actualizada el 2026-11-18): tagUser,
# tagHoldAdmin, iam.admin, iam.securityAdmin, iam.serviceAccountAdmin, iam.workspacePoolAdmin,
# storage.legacyBucketOwner, cuatro roles de agentes de servicio, y cloudkms.admin y storage.admin
# (*TagBinding de llaveros y buckets); tagAdmin trae el IAM de las etiquetas.
run "ningun_rol_del_pipeline_liga_etiquetas" {
  command = plan

  assert {
    condition = alltrue([for k, b in module.stage_iam.bindings : !contains([
      "roles/resourcemanager.tagUser", "roles/resourcemanager.tagAdmin", "roles/resourcemanager.tagHoldAdmin",
      "roles/iam.admin", "roles/iam.securityAdmin", "roles/iam.serviceAccountAdmin", "roles/iam.workspacePoolAdmin",
      "roles/storage.legacyBucketOwner", "roles/owner", "roles/editor",
      "roles/container.serviceAgent", "roles/compute.instanceGroupManagerServiceAgent",
      "roles/cloudkmskacls.serviceAgent", "roles/storage.malwareScannerServiceAgent",
    ], b.role) if contains(["project", "organization"], b.scope)])
    error_message = "Ninguna cuenta del pipeline puede tener tagUser, tagAdmin ni un rol predefinido con *TagBinding o tagValueBindings."
  }
  # cloudkms.admin y storage.admin traen *TagBinding de llaveros y buckets: solo con una condición
  # que deja fuera el llavero y el bucket del estado (y la regla 1 de la denegación niega las
  # etiquetas del bucket protegido).
  assert {
    condition = alltrue([for k, b in module.stage_iam.bindings : (
      b.role == "roles/cloudkms.admin" ? try(module.stage_iam.conditions[k].expression, "") == "!resource.name.startsWith(\"projects/example-project-id/locations/us/keyRings/bnt-bootstrap-\")" : (
        b.role == "roles/storage.admin" ? (
          startswith(try(module.stage_iam.conditions[k].expression, ""), "resource.name.startsWith(\"projects/_/buckets/bnt-") &&
          !strcontains(try(module.stage_iam.conditions[k].expression, "bnt-bootstrap"), "bnt-bootstrap")
        ) : true
      )
    )])
    error_message = "cloudkms.admin y storage.admin solo con una condición que excluya el llavero y el bucket del estado."
  }
  # Roles personalizados: ninguno liga, quita ni retiene etiquetas.
  assert {
    condition = alltrue(flatten([for k, r in google_project_iam_custom_role.this : [
      for p in r.permissions : !strcontains(p, "TagBinding") && !startswith(p, "resourcemanager.tagValueBindings.") && !startswith(p, "resourcemanager.tagHolds.")
    ]]))
    error_message = "Ningún rol personalizado puede tener *TagBinding, tagValueBindings ni tagHolds."
  }
  assert {
    condition = alltrue([
      contains(google_project_iam_custom_role.this["network_tag_manager"].permissions, "resourcemanager.tagValues.setIamPolicy"),
      contains(google_project_iam_custom_role.this["network_tag_manager"].permissions, "resourcemanager.tagKeys.create"),
      length(google_project_iam_custom_role.this["network_tag_manager"].permissions) == 14,
    ])
    error_message = "TfNetworkTagManager administra claves, valores y su IAM, y nada más."
  }
  # Las cuentas de cargas no tienen ningún rol de etiquetas de proyecto: el spoke les da tagUser
  # solo sobre sus valores.
  assert {
    condition     = length([for k, b in module.stage_iam.bindings : k if startswith(k, "project|3-workloads/") && strcontains(b.role, "resourcemanager.tag")]) == 0
    error_message = "tf-wl-<env> no tiene roles de etiquetas en el proyecto."
  }
}

run "sin_etiquetas" {
  command = plan

  variables {
    enable_protection_tags = false
  }

  assert {
    condition = alltrue([
      length(google_tags_tag_key.protection) == 0,
      length(google_tags_tag_binding.pipeline_accounts) == 0,
      length(google_iam_deny_policy.pipeline["this"].rules) == 2,
      length(google_iam_deny_policy.pipeline["this"].rules[0].deny_rule[0].denial_condition) == 0,
      length(google_iam_deny_policy.pipeline["this"].rules[1].deny_rule[0].denial_condition) == 0,
    ])
    error_message = "Sin etiquetas, la denegación solo lleva las reglas sin condición."
  }
}

run "sin_denegacion" {
  command = plan

  variables {
    enable_deny_policy = false
  }

  assert {
    condition     = length(google_iam_deny_policy.pipeline) == 0 && length(google_tags_tag_key.protection) == 1
    error_message = "enable_deny_policy = false quita solo la política de denegación."
  }
}

# Con organización, las políticas de organización y el perímetro los aplica esta etapa (la
# persona), no el pipeline: ninguna cuenta del pipeline recibe un rol de organización ni de la
# política de acceso.
run "con_organizacion_y_politica_de_acceso" {
  command = plan

  variables {
    org_id                = "000000000000"
    directory_customer_id = "C00000000"
    access_policy_id      = "555555555555"
  }

  assert {
    condition = alltrue([
      module.org_policies[0].policy_parent == "projects/example-project-id",
      length(module.org_policies[0].policy_names) == 8,
      contains(keys(module.org_policies[0].policy_names), "iam.allowedPolicyMemberDomains"),
      output.org_policies_enabled == true,
    ])
    error_message = "Con organización, esta etapa aplica las ocho políticas de organización al proyecto."
  }
  assert {
    condition = alltrue([
      output.vpc_sc_perimeter_name == "accessPolicies/555555555555/servicePerimeters/bnt_common_sec_perimeter",
      module.vpc_sc[0].enforced == false,
      length(module.vpc_sc[0].spec_ingress_policies) == 1,
      length(module.vpc_sc[0].status_ingress_policies) == 0,
    ])
    error_message = "Con política de acceso, esta etapa crea el perímetro en dry-run alrededor de todo el proyecto."
  }
  assert {
    condition = alltrue([
      length([for b in values(module.stage_iam.bindings) : b if b.scope == "organization"]) == 0,
      length([for b in values(module.stage_iam.bindings) : b if strcontains(b.role, "orgpolicy") || strcontains(b.role, "accesscontextmanager")]) == 0,
    ])
    error_message = "Ninguna cuenta del pipeline recibe roles de organización ni de la política de acceso."
  }
}

run "politica_de_acceso_sin_organizacion" {
  command = plan

  variables {
    access_policy_id = "555555555555"
  }

  expect_failures = [var.access_policy_id]
}

run "cliente_de_directorio_sin_organizacion" {
  command = plan

  variables {
    directory_customer_id = "C00000000"
  }

  expect_failures = [var.directory_customer_id]
}

run "prefix_gcp" {
  command = plan

  variables {
    prefix = "gcp"
  }

  expect_failures = [var.prefix]
}

run "prefix_invalido" {
  command = plan

  variables {
    prefix = "Empresa1"
  }

  expect_failures = [var.prefix]
}

run "repositorio_invalido" {
  command = plan

  variables {
    github_repository = "sin-barra"
  }

  expect_failures = [var.github_repository]
}

run "id_de_repositorio_invalido" {
  command = plan

  variables {
    github_repository_id = "example-org/example-repo"
  }

  expect_failures = [var.github_repository_id]
}

run "estado_en_doble_region" {
  command = plan

  variables {
    state_bucket_dual_regions = ["us-central1", "us-east4"]
  }

  assert {
    condition = alltrue([
      google_storage_bucket.state.location == "US",
      google_storage_bucket.state.custom_placement_config[0].data_locations == toset(["US-CENTRAL1", "US-EAST4"]),
      google_storage_bucket.state.rpo == "ASYNC_TURBO",
      module.state_kms.location == "us",
    ])
    error_message = "Doble región configurable: primaria y DR dentro de US, replicación turbo y llave en us."
  }
}

run "doble_region_sin_la_primaria" {
  command = plan

  variables {
    state_bucket_dual_regions = ["us-east4", "us-west1"]
  }

  expect_failures = [google_storage_bucket.state]
}

run "doble_region_sin_la_de_dr" {
  command = plan

  variables {
    state_bucket_dual_regions = ["us-central1", "us-west1"]
  }

  expect_failures = [google_storage_bucket.state]
}

run "ubicacion_regional_del_estado" {
  command = plan

  variables {
    state_bucket_location = "us-central1"
  }

  expect_failures = [var.state_bucket_location]
}

run "proyecto_invalido" {
  command = plan

  variables {
    project_id = "Proyecto"
  }

  expect_failures = [var.project_id]
}

run "dr_igual_a_primaria" {
  command = plan

  variables {
    dr_region = "us-central1"
  }

  expect_failures = [var.dr_region]
}

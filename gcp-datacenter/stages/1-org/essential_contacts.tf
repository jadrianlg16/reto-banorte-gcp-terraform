# Contactos esenciales de la organización (CIS 1.17; detector ESSENTIAL_CONTACTS_NOT_CONFIGURED,
# que pide un contacto para Legal, Security, Suspension y Technical). Un contacto por grupo de
# `groups`, con las categorías de `essential_contacts`; nunca personas. La cuenta de la etapa
# necesita roles/essentialcontacts.admin en la organización (lo da la etapa 0) y la API
# essentialcontacts.googleapis.com en el proyecto de cuota, que es el semilla (providers.tf).
# Fuentes: https://docs.cloud.google.com/resource-manager/docs/managing-notification-contacts
# y la página de hallazgos de Security Health Analytics.
# VERIFICAR-EN-APPLY: que la API acepte los grupos como contactos y el idioma
# essential_contacts_language (pendiente 57).
resource "google_essential_contacts_contact" "org" {
  for_each = var.essential_contacts

  parent                              = local.org_parent
  email                               = var.groups[each.key]
  language_tag                        = var.essential_contacts_language
  notification_category_subscriptions = sort(distinct(each.value))
}

###############################################################################
# File:        stacks/60-tags/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the tags stack.
###############################################################################

output "tag_keys" {
  description = "Map of tag key short_name → resource name ('tagKeys/<numeric_id>'). Consumed by downstream stacks that bind tags to resources via google_tags_tag_binding or by hierarchical firewall policies that reference the tag."
  value = {
    for k, tk in google_tags_tag_key.keys : k => tk.name
  }
}

output "tag_key_ids_numeric" {
  description = "Map of tag key short_name → numeric ID only (the '123456789012' part). Convenience for consumers that need just the number for API paths."
  value = {
    for k, tk in google_tags_tag_key.keys : k => split("/", tk.name)[1]
  }
}

output "tag_values" {
  description = "Map of 'key/value' composite key → resource name ('tagValues/<numeric_id>'). Consumers reference this to bind a specific value to a resource."
  value = {
    for k, tv in google_tags_tag_value.values : k => tv.name
  }
}

output "tag_catalog" {
  description = "Human-readable summary of the provisioned catalog — { key_name = [value1, value2, ...] }. Useful for downstream policies that enumerate legal values before binding."
  value = {
    for key_name, key_spec in local.all_tag_keys :
    key_name => key_spec.values
  }
}

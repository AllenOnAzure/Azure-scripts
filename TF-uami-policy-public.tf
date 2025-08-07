terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "<yourSubID>"
}

variable "subscription_id" {
  default = "<yourSubID>"
}

variable "location" {
  default = "uksouth"
}

variable "resource_group_name" {
  default = "allen-uami-rg"
}

variable "identity_name" {
  default = "allen-auto-assign-uami"
}

variable "policy_name" {
  default = "allen-auto-assign-uami-policy"
}

resource "azurerm_resource_group" "uami_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_user_assigned_identity" "uami" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = azurerm_resource_group.uami_rg.name
}

resource "azurerm_policy_definition" "auto_assign_uami" {
  name         = var.policy_name
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Allen-Auto-Assign-UAMI-to-VMs"

  policy_rule = jsonencode({
    "if" : {
      "allOf" : [
        {
          "field" : "type",
          "equals" : "Microsoft.Compute/virtualMachines"
        },
        {
          "field" : "identity.type",
          "notEquals" : "UserAssigned"
        }
      ]
    },
    "then" : {
      "effect" : "modify",
      "details" : {
        "roleDefinitionIds" : [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ],
        "operations" : [
          {
            "operation" : "add",
            "field" : "identity.userAssignedIdentities",
            "value" : {
              "${azurerm_user_assigned_identity.uami.id}" : {}
            }
          },
          {
            "operation" : "addOrReplace",
            "field" : "identity.type",
            "value" : "UserAssigned"
          }
        ]
      }
    }
  })
}

data "azurerm_subscription" "current" {}

resource "azurerm_subscription_policy_assignment" "assign_policy" {
  name                 = "Allen-Auto-Assign-UAMI-to-VMs"
  policy_definition_id = azurerm_policy_definition.auto_assign_uami.id
  subscription_id      = data.azurerm_subscription.current.id
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }
  location = var.location
}



##VERIFICATION THAT VMS HAVE UAMI:
#az vm show --name a1 --resource-group allens-ama-testvms --query identity

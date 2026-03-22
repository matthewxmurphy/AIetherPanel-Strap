#!/usr/bin/env bash

aetherpanel_step_services() {
  configure_fail2ban
  enable_services
  record_host_facts
}

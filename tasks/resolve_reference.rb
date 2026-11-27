#!/usr/bin/env ruby
# frozen_string_literal: true

# Bolt inventory plugin task: prints the NodeRings VMs as Bolt targets.
# Bolt runs it on the controller with the plugin's options as parameters.

require 'json'

input = $stdin.read.to_s
params = JSON.parse(input.strip.empty? ? '{}' : input)
lib = File.join(params.fetch('_installdir'), 'noderings', 'lib', 'puppet_x', 'noderings')
require File.join(lib, 'bolt_inventory')

begin
  targets = PuppetX::Noderings::BoltInventory.resolve(params)
  puts({ value: targets }.to_json)
rescue PuppetX::Noderings::UsageError, PuppetX::Noderings::APIError, *PuppetX::Noderings::CONNECTION_ERRORS => e
  puts({ _error: { msg: e.message, kind: 'noderings/inventory-error', details: {} } }.to_json)
  exit 1
end

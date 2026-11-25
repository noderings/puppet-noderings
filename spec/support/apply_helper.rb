# frozen_string_literal: true

# Applies resources the way an agent run does (prefetch, sync checks, flush)
# and returns the transaction report.
module ApplyHelper
  def resource(type, title, params = {})
    Puppet::Type.type(type).new(params.merge(title: title))
  end

  def apply(*resources)
    catalog = Puppet::Resource::Catalog.new
    resources.flatten.each { |r| catalog.add_resource(r) }
    catalog.host_config = false
    transaction = catalog.apply
    transaction.report
  end

  # Rebuilds the resources from scratch, as a fresh agent run would.
  def apply_fresh(&block)
    PuppetX::Noderings::Config.reset!
    apply(*block.call)
  end

  def changed(report)
    report.resource_statuses.values.select(&:changed).map(&:resource)
  end

  def failed(report)
    report.resource_statuses.values.select(&:failed).map { |s| [s.resource, s.events.map(&:message)] }
  end
end

RSpec.configure { |c| c.include ApplyHelper }

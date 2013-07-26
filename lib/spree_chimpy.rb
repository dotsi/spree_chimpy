require 'spree_core'
require 'spree/chimpy/engine'
require 'spree/chimpy/subscription'
require 'spree/chimpy/workers/delayed_job'
require 'hominid'

module Spree::Chimpy
  extend self

  API_VERSION = '1.3'

  def config(&block)
    yield(Spree::Chimpy::Config)
  end

  def enqueue(event, object)
    payload = {class: object.class.name, id: object.id, object: object}
    ActiveSupport::Notifications.instrument("spree.chimpy.#{event}", payload)
  end

  def log(message)
    Rails.logger.info "spree_chimpy: #{message}"
  end

  def configured?
    Config.key.present?
  end

  def list
    Interface::List.new(Config.key,
                        Config.list_name,
                        Config.customer_segment_name) if configured?
  end

  def orders
    Interface::Orders.new(Config.key) if configured?
  end

  def list_exists?
    list.list_id
  end

  def segment_exists?
    list.segment_id
  end

  def create_segment
    list.create_segment
  end

  def sync_merge_vars
    existing   = list.merge_vars + %w(EMAIL)
    merge_vars = Config.merge_vars.except(*existing)

    merge_vars.each do |tag, method|
      list.add_merge_var(tag.upcase, method.to_s.humanize.titleize)
    end
  end

  def merge_vars(model)
    array = Config.merge_vars.except('EMAIL').map do |tag, method|
      [tag, model.send(method).to_s]
    end

    Hash[array]
  end

  def ensure_list
    if list_exists?
      sync_merge_vars
    else
      Rails.logger.error("spree_chimpy: hmm.. a list named `#{list_name=''}` was not found. please add it and reboot the app")
    end
  end

  def ensure_segment
    unless segment_exists?
      create_segment
      #Rails.logger.error("spree_chimpy: hmm.. a static segment named `#{customer_segment_name}` was not found. Creating it now")
    end
  end

  def handle_event(event, payload = {})
    payload[:event] = event

    if defined?(::Delayed::Job)
      ::Delayed::Job.enqueue(Spree::Chimpy::Workers::DelayedJob.new(payload))
    else
      perform(payload)
    end
  end

  def perform(payload)
    return unless configured?

    event  = payload[:event].to_sym
    object = payload[:object] || payload[:class].constantize.find(payload[:id])

    case event
    when :order
      orders.sync(object)
    when :subscribe
      list.subscribe(object.email, merge_vars(object), customer: object.is_a?(Spree.user_class))
    when :unsubscribe
      list.unsubscribe(object.email)
    end
  end
end

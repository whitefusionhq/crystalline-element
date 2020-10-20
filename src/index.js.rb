import [ LitElement, html ], from: "lit-element"

# Lambda for determining default node action
default_action_for_node = ->(node) do
  case node.node_name.downcase()
  when :form
    :submit
  when :input, :textarea
    return node.get_attribute(:type) == :submit ? :click : :input
  when :select
    :change
  else
    :click
  end
end

export class CrystallineElement < LitElement
  def self.define(name, options = {})
    self.prototype.create_render_root = `"function() { return this }"` if options[:shadow_dom] == false

    if options[:pass_through]
      self.render = ->() { ->() {} } # no-op
    end

    custom_elements.define(name, self)
  end

  def initialize
    super

    # Set initial default values
    self.class.properties.each_pair do |property, config|
      self[property] = config[:default]
    end if self.class.properties

    # button@identifier => button[custom-element-id='identifier']
    swap_in_id = ->(selector) do
      selector.gsub(/@([a-z-]+)/, "[#{self.node_name}-id='$1']")
    end

    # Add queries as instance properties
    self.class.queries.each_pair do |name, selector|
      if selector.is_a?(Array)
        selector = swap_in_id(selector[0])
        Object.define_property(self, "_#{name}", {
          get: ->() do
            Array(self.query_selector_all(selector)).select do |node|
              @nested_nodes.select do |nested_node|
                nested_node.contains? node
              end.length == 0
            end
          end
        })
      else
        selector = swap_in_id(selector)
        Object.define_property(self, "_#{name}", {
          get: ->() do
            node = self.query_selector(selector)
            node if @nested_nodes.select do |nested_node|
              nested_node.contains? node
            end.length == 0
          end
        })
      end
    end if self.class.queries

    self
  end

  # Set up MutationObserver and get ready to look for event definitions
  def connected_callback()
    super

    @registered_actions = []
    @nested_nodes = []

    self.handle_nodechanges([{
      type: :attributes,
      target: self
    }])

    @node_observer = new MutationObserver(self.handle_nodechanges.bind(self))
    config = { attributes: true, childList: true, subtree: true }
    @node_observer.observe self, config
  end

  def disconnected_callback()
    super

    @node_observer.disconnect()
    @registered_actions = []
    @nested_nodes = []
  end

  # Callback for MutationObserver
  def handle_nodechanges(changes)
    self_name = self.node_name.downcase()
    action_attr = "#{self_name}-action"

    # Lambda to set up event listeners
    setup_listener = ->(node, include_self_node) do
      if !include_self_node and node.node_name == self.node_name # don't touch nested elements
        @nested_nodes.push node
        next
      end

      # make sure node isn't inside a nested node
      next if @nested_nodes.find do |nested_node|
        nested_node.contains? node
      end

      if node.has_attribute(action_attr)
        node.get_attribute(action_attr).split(" ").each do |action_pair|
          action_event, action_name = action_pair.split("->")
          unless defined? action_name
            action_name = action_event
            action_event = default_action_for_node(node)
          end
          action_event = action_event.strip()
          next if @registered_actions.find {|action| action.node == node && action.event == action_event && action.name == action_name }
          node.add_event_listener(action_event, self[action_name].bind(self))
          @registered_actions.push({
            node: node,
            event: action_event,
            name: action_name
          })
        end
      end
    end

    unless @node_observer
      # First run situation, check all child nodes
      self.query_selector_all("*").each do |node|
        setup_listener(node, false)
      end
    end

    # Loop through all the mutations
    changes.each do |change|
      if change.type == :child_list
        change.added_nodes.each do |node|
          next unless node.node_type == 1 # only process element nodes
          setup_listener(node, false)
        end
        change.removed_nodes.each do |node|
          # clear out removed nested nodes
          next unless node.node_name == self.node_name
          @nested_nodes = @nested_nodes.select do |nested_node|
            nested_node != node
          end
        end
      elsif change.type == :attributes
        setup_listener(change.target, true)
      end
    end
  end

  def render()
    html "<slot></slot>"
  end
end

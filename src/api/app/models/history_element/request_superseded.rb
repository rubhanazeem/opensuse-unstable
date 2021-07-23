module HistoryElement
  class RequestSuperseded < HistoryElement::Request
    def color
      'green'
    end

    def description
      desc = 'Request got superseded'
      desc << ' by request ' << description_extension if description_extension
      desc
    end

    def user_action
      'superseded request'
    end

    def initialize(a)
      super
    end
  end
end

# == Schema Information
#
# Table name: history_elements
#
#  id                    :integer          not null, primary key
#  comment               :text(65535)
#  description_extension :string(255)
#  type                  :string(255)      not null, indexed, indexed => [op_object_id]
#  created_at            :datetime         not null, indexed
#  op_object_id          :integer          not null, indexed => [type]
#  user_id               :integer          not null
#
# Indexes
#
#  index_history_elements_on_created_at  (created_at)
#  index_history_elements_on_type        (type)
#  index_search                          (op_object_id,type)
#

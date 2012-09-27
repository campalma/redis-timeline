module Timeline::Track
  extend ActiveSupport::Concern

  module ClassMethods

    require "set"

    def track(name, options={})
      @name = name
      @callback = options.delete :on
      @callback ||= :create
      @actor = options.delete :actor
      @actor ||= :creator
      @object = options.delete :object
      @target = options.delete :target
      @followers = options.delete :followers
      @followers ||= :followers
      @extra_fields = options.delete :extra_fields
      @mentionable = options.delete :mentionable

      method_name = "track_#{@name}_after_#{@callback}".to_sym
      define_activity_method method_name, actor: @actor, object: @object, target: @target, followers: @followers, extra_fields: @extra_fields, verb: name, mentionable: @mentionable

      send "after_#{@callback}".to_sym, method_name, if: options.delete(:if)
    end

    private
      def define_activity_method(method_name, options={})
        define_method method_name do
          @actor = send(options[:actor])
          @fields_for = {}
          @object = set_object(options[:object])
          @target = send(options[:target].to_sym)
          unless(@target.respond_to?(:length))
            @target = [@target]
          end
          @extra_fields = options[:extra_fields]
          @followers = send(options[:followers].to_sym)
          @mentionable = options[:mentionable]
          add_activity activity(verb: options[:verb])
        end
      end
  end

  protected
    def activity(options={})
      {
        verb: options[:verb],
        actor: options_for(@actor),
        object: options_for(@object),
        target: options_for_targets(@target),
        created_at: Time.now
      }
    end

    def add_activity(activity_item)
      redis_add "global:activity", activity_item
      add_activity_to_user(activity_item[:actor][:id], activity_item)
      add_activity_by_user(activity_item[:actor][:id], activity_item)
      add_mentions(activity_item)
      add_activity_to_followers(activity_item) if @followers.any?
      add_activity_to_targets(activity_item) if @target.any?
    end

    def add_activity_by_user(user_id, activity_item)
      redis_add "user:id:#{user_id}:profile", activity_item
    end

    def add_activity_to_user(user_id, activity_item)
      redis_add "user:id:#{user_id}:network", activity_item
    end

    def add_activity_to_followers(activity_item)
      @followers = @followers.to_set - @target.to_set
      @followers.each do |follower|
        if follower != @actor
          add_activity_to_user(follower.id, activity_item)
        end
      end
    end

    def add_activity_to_targets(activity_item)
      activity_item[:verb] = "inv_"+ activity_item[:verb].to_s
      activity_item[:verb] = activity_item[:verb].to_sym
      activity_item[:target] = [options_for(@actor)]
      @target.each do |t|
        if t != @actor
          activity_item[:actor] = options_for(t)
          add_activity_by_user(t.id, activity_item)
          add_activity_to_user(t.id, activity_item)
        end
      end
    end

    def add_mentions(activity_item)
      return unless @mentionable and @object.send(@mentionable)
      @object.send(@mentionable).scan(/@\w+/).each do |mention|
        if user = @actor.class.find_by_username(mention[1..-1])
          add_mention_to_user(user.id, activity_item)
        end
      end
    end

    def add_mention_to_user(user_id, activity_item)
      redis_add "user:id:#{user_id}:mentions", activity_item
    end

    def extra_fields_for(object)
      if @extra_fields.nil?
        return {}
      else
        extra = {}
        extra[@extra_fields.to_sym] = send(@extra_fields.to_sym)
        return extra
      end
    end

    def options_for(timeline_object)
      if !timeline_object.nil?
        {
          id: timeline_object.id,
          class: timeline_object.class.to_s,
          display_name: timeline_object.to_s
        }.merge(extra_fields_for(timeline_object))
      else
        nil
      end
    end

    def options_for_targets(targets)
      targets.collect do |t|
        {
          id: t.id,
          class: t.class.to_s,
          display_name: t.to_s
        }
      end
    end

    def redis_add(list, activity_item)
      Timeline.redis.lpush list, Timeline.encode(activity_item)
    end

    def set_object(object)
      case
      when object.is_a?(Symbol)
        send(object)
      when object.is_a?(Array)
        @fields_for[self.class.to_s.downcase.to_sym] = object
        self
      else
        self
      end
    end

end
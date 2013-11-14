module LowCardTables
  module HasLowCardTable
    # Unlike the LowCardAssociationsManager, the LowCardObjectsManager belongs to a particular _instance_ of a model
    # class that refers to a low-card table. Its responsibility is straightforward: it holds onto the actual instances
    # of the low-card class that we return in response to someone accessing a low-card association. (More concretely:
    # when you say my_user.status, you get back an instance of UserStatus; if you say my_user.status again, you get back
    # the same instance of UserStatus. This class is responsible for creating that object in the first place, and
    # holding onto it so that the same one gets returned all the time.)
    #
    # In an ordinary Rails association, you'd get back live, normal instances of the associated class -- just like if
    # you'd said, say, <tt>UserStatus.find(...)</tt> in the first place. However, this is inappropriate for low-card
    # associations, because the whole 'trick' of the low-card system is that changing the attributes of the
    # conceptually-associated +UserStatus+ object actually just changes <em>which +UserStatus+ object you're pointing
    # at</em>, rather than actually changing a +UserStatus+ row at all.
    #
    # We perform a simple trick here instead, composed of three parts:
    #
    # * Returned objects from low-card associations are actually clones (Object#dup) of the normal low-card objects
    #   you'd ordinarily get; this is necessary so that clients can assign attributes to them in any way they want,
    #   and there's no "crosstalk".
    # * Returned objects have their ID removed (through a simple <tt>object.id = nil</tt>); this prevents a whole class
    #   of common coding mistakes. Say you retrieve the low-card object associated with a particular referring object,
    #   and then modify some of its attributes. Without this change, you'd now be in a situation where you have an
    #   associated ActiveRecord object (the low-card object) that has a particular set of attributes, and a particular
    #   ID...and yet, when you call #save -- which will succeed! -- that particular ID doesn't have that set of
    #   attributes at all. It would be way too easy to write code that looks completely correct, and yet fails; for
    #   example, you could grab the ID of that associated object and assign it to other referring rows. So we strip the
    #   ID off completely.
    # * Returned objects cannot be directly saved at all; if you call #save or #save! on them, you'll get an exception,
    #   telling you not to do that. The low-card system itself needs to be in complete control of what rows get created,
    #   and be able to change referring IDs instead.
    #
    # These tricks actually happen in LowCardTables::HasLowCardTable::LowCardAssociation#create_low_card_object_for
    # and LowCardTables::LowCardTable::Base#_low_card_disable_save_when_needed!, but it makes sense to document them
    # here, since this class is most clearly given this responsibility.
    class LowCardObjectsManager
      # Creates a new instance of the LowCardObjectsManager, tied to a particular _instance_ of a low-card model.
      # That is, +model_instance+ should be an instance of +UserStatus+ or something similar.
      def initialize(model_instance)
        @model_instance = model_instance
        @objects = { }
      end

      # Returns the low-card object that corresponds to the given LowCardAssociation for this model instance.
      def object_for(association)
        association_name = association.association_name.to_s.strip.downcase
        @objects[association_name] ||= begin
          association = model_instance.class._low_card_associations_manager._low_card_association(association_name)
          association.create_low_card_object_for(model_instance)
        end
      end

      # Returns the foreign key for the given LowCardAssociation for this model instance. This wouldn't really have to
      # go through this class for any great reason right now, but, given that #set_foreign_key_for does, it makes a lot
      # of sense to keep the logic here.
      def foreign_key_for(association)
        model_instance[association.foreign_key_column_name]
      end

      # Sets the foreign key for the given LowCardAssociation for this model instance. We allow users to do this
      # directly (e.g., <tt>my_user.user_status_id = 17</tt>) so that they can, for example, store +UserStatus+ IDs
      # out-of-band (in memcache, Redis, or whatever) for any reasons they want. When they do assign the foreign-key
      # value, we need to invalidate the associated low-card object, since any previous data there is now no longer
      # valid.
      def set_foreign_key_for(association, new_value)
        model_instance[association.foreign_key_column_name] = new_value
        invalidate_object_for(association)
        new_value
      end

      private
      # Removes the mapped object for a given association -- this simply deletes the object from our hash.
      def invalidate_object_for(association)
        @objects.delete(association.association_name)
      end

      attr_reader :model_instance
    end
  end
end

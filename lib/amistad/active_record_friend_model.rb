require 'squeel'

module Amistad
  module ActiveRecordFriendModel
    extend ActiveSupport::Concern

    included do
      #####################################################################################
      # friendships
      #####################################################################################
      has_many  :friendships,
        :class_name => "Amistad::Friendships::#{Amistad.friendship_model}",
        :foreign_key => "friendable_id"

      has_many  :pending_invited,
        :through => :friendships,
        :source => :friend,
        :conditions => { :'friendships.pending' => true, :'friendships.blocker_id' => nil }

      has_many  :invited,
        :through => :friendships,
        :source => :friend,
        :conditions => { :'friendships.pending' => false, :'friendships.blocker_id' => nil }

      #####################################################################################
      # inverse friendships
      #####################################################################################
      has_many  :inverse_friendships,
        :class_name => "Amistad::Friendships::#{Amistad.friendship_model}",
        :foreign_key => "friend_id"

      has_many  :pending_invited_by,
        :through => :inverse_friendships,
        :source => :friendable,
        :conditions => { :'friendships.pending' => true, :'friendships.blocker_id' => nil }

      has_many  :invited_by,
        :through => :inverse_friendships,
        :source => :friendable,
        :conditions => { :'friendships.pending' => false, :'friendships.blocker_id' => nil }

      #####################################################################################
      # blocked friendships
      #####################################################################################
      has_many  :blocked_friendships,
        :class_name => "Amistad::Friendships::#{Amistad.friendship_model}",
        :foreign_key => "blocker_id"

      has_many  :blockades,
        :through => :blocked_friendships,
        :source => :friend,
        :conditions => "friend_id <> blocker_id"

      has_many  :blockades_by,
        :through => :blocked_friendships,
        :source => :friendable,
        :conditions => "friendable_id <> blocker_id"
    end

    # suggest a user to become a friend. If the operation succeeds, the method returns true, else false
    def invite(user)
      return false if user == self || find_any_friendship_with(user)
      Amistad.friendship_class.new{ |f| f.friendable = self ; f.friend = user }.save
    end

    # approve a friendship invitation. If the operation succeeds, the method returns true, else false
    def approve(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil? || gave_invite?(user)
      friendship.update_attribute(:pending, false)
    end

    # deletes a friendship
    def remove_friendship(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil?
      friendship.destroy
      self.reload && user.reload if friendship.destroyed?
    end

    # returns the list of approved friends
    def friends
      friendship_model = Amistad::Friendships.const_get(:"#{Amistad.friendship_model}")

      approved_friendships = friendship_model.where{
        ( friendable_id == my{id} ) &
        ( pending       == false  ) &
        ( blocker_id    == nil    )
      }

      approved_inverse_friendships = friendship_model.where{
        ( friend_id  == my{id} ) &
        ( pending    == false   ) &
        ( blocker_id == nil     )
      }

      self.class.where{
        ( id.in(approved_friendships.select{friend_id})              ) |
        ( id.in(approved_inverse_friendships.select{friendable_id})  )
      }
    end

    # total # of invited and invited_by without association loading
    def total_friends
      self.invited(false).count + self.invited_by(false).count
    end

    # blocks a friendship
    def block(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil? || !friendship.can_block?(self)
      friendship.update_attribute(:blocker, self)
    end

    # unblocks a friendship
    def unblock(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil? || !friendship.can_unblock?(self)
      friendship.update_attribute(:blocker, nil)
    end

    # returns the list of blocked friends
    def blocked
      self.reload
      self.blockades + self.blockades_by
    end

    # total # of blockades and blockedes_by without association loading
    def total_blocked
      self.blockades(false).count + self.blockades_by(false).count
    end

    # checks if a user is blocked
    def blocked?(user)
      blocked.include?(user)
    end

    # checks if a user is a friend
    def friend_with?(user)
      friends.include?(user)
    end

    # checks if a current user is connected to given user
    def connected_with?(user)
      find_any_friendship_with(user).present?
    end

    #### Potential Friends Addition ####
    # Could have much better PERF with calculating only ids for all methods
    # instead of using full objects

    # Find all friends of users friends then remove current friends and any
    # blocked friendships
    def potential_friends
      friends_of_friends - not_potential_friends
    end

    #Find all friends of direct Friends
    def friends_of_friends
      foaf ||= []
      friends.each do |friend|
        foaf << friend.friends
      end
      foaf.flatten
    end

    def not_self_in_friendship(friendship, user)
      (friendship.friend == user) ? friendship.friendable : friendship.friend
    end

    # returns all current friends (regardless of status)
    # and any additional ignored friends
    def not_potential_friends
      @not_potential_friends ||= begin
        friends + blocked + [self]
      end
    end

    def mutual_friends(user)
      friends & find_any_friendship_with(user) if self != user
    end

    def mutual_friends_count(user)
      mutual_friends(user).count
    end

    # checks if a current user received invitation from given user
    def given_invite_by?(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil?
      friendship.friendable_id == user.id
    end

    # checks if a current user invited given user
    def gave_invite?(user)
      friendship = find_any_friendship_with(user)
      return false if friendship.nil?
      friendship.friend_id == user.id
    end

    # return the list of the ones among its friends which are also friend with the given use
    def common_friends_with(user)
      self.friends & user.friends
    end

    # returns friendship with given user or nil
    def find_any_friendship_with(user)
      friendship = Amistad.friendship_class.where(:friendable_id => self.id, :friend_id => user.id).first
      if friendship.nil?
        friendship = Amistad.friendship_class.where(:friendable_id => user.id, :friend_id => self.id).first
      end
      friendship
    end
  end
end

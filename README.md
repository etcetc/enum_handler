# EnumHandler

The EnumHandler helps manage an enum for an active record class.
The assumption is that the actual values are stored as integers or strings in the DB, but you want to use symbols in the rest of
the code. For example, if you have a status field, you might want to store the values as 0 for pending, 1 for active, and 2 for 
terminated, but you want to reference them as :active, :terminated, etc.

EnumHandler then gives you a number of syntactic niceties for dealing with the enums.  For example, it automatically scopes the class so it's easy to query for all instances that have the attribute set to a particular enum, for example, User.active will pull out all the active users.

You can use this module two ways.  
In the more common case, you simply want 'enum'-ify an attribute in the existing activeRecord, you simply indicate:

    define_enum :attribute, values_hash (symbol => underlying code), <options>
for example:
    class User < ActiveRecord::Base
       include EnumHandler
       define_enum :status, { :active => 0, :suspended => 1, :terminated => -1}
    end
or else, if you are storing the attribute as a string:

     define_enum :attribute, symbol_values_array
     
e.g. 
     define_enum :kind, [:normal, :test, :admin]

In the first case, the values are saved as integers (the integer constraint is not enforced by the system - it's just common)
In the second case, the symbol values are stored as strings (as if the to_s had been used on the symbol)

     
## Sugar
There are a few nice things that come with enums:

1. The attribute will only accept defined enum values, else will throw an exception
2. You can query for all instances where the attribute is a particular enum value, for example, *User.status_active* will return all users with status set to active.  Similarly, you can as for *User.status_not_active* to retrieve the users who do not have their status attribute set to active (see primary option below also)
3. You can query an instance for the enum value, for example, *user.is_status_active?* will return if the user has status active 

## Options

define_enum takes a few options:

    :primary => true
    :sets => { set_symbol  => [:value1,:value2]}

Indicating that an enum is primary means that we need to specify the attribute name in the synctatic conveniences.  For example, if we define the status enum as

    define_enum :status, { active: 0, suspended: 1, terminated: -1}, primary: true

We can then query for the active users simply with *User.active*.  Likewise, we can ask if a particular user is active via *user.is_active?*._

Sets allow you to put multiple attribute values into a set, so, for example, you may consider that users that have status *suspended*
or *terminated* are *inactive*.  We can then define this as:

    define_enum :status, { active: 0, suspended: 1, terminated: -1}, sets: {inactive: [:suspended,:terminated]}, primary: true
  
Now you can use the same formalism with the set as with the individual attribute values:
  *User.inactive* will return the list of inactive users
  *user.is_inactive?*  will return if the user is inactive, that is, suspended or terminated_

 
## Note
defin\_enum creates a class variable *eh\_params* in the including class.  This is used to save various characteristics of the enums that are defined.  
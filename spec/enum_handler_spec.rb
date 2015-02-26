require 'spec_helper'
describe "EnumHandler" do
  before(:all) do 
    # Create the models
    class Book < ActiveRecord::Base
      include EnumHandler
      define_enum :condition, {mint: 0,used: 1,excellent: 2, almost_new: 3}, primary:true, sets: {primo: [:mint,:excellent,:almost_new]}
    end
    build_model_table(Book,condition: :integer,user_id: :integer)
    class User < ActiveRecord::Base
      include EnumHandler
      has_many :books
      define_enum :status, [:active,:registration_pending, :suspended,:terminated], primary: true, sets:{inactive: [:registration_pending, :suspended,:terminated]}
      define_enum :role, [:customer,:supplier]
      scope :with_name_like, lambda { |x| where("name like '%#{x}%'") }
    end
    build_model_table(User,status: :string, role: :string, name: :string)
    4.times { |i| User.create(status: :registration_pending, role: :customer, name: "Joe #{i}") }
    3.times { |i| User.create(status: :active, role: :customer, name: "Fred #{i}") }
    2.times { |i| User.create(status: :suspended, role: :supplier, name: "Joe blow #{i}") }
    1.times { User.create(status: :terminated, role: :customer) }
    User.first.books << Book.create(condition: :mint)
    User.first.books << Book.create(condition: :mint)
    User.first.books << Book.create(condition: :used)
    User.first.books << Book.create(condition: :almost_new)


    # We create this class to make sure that our enum_handler doesn't mess up normal searches
    class NoEnum < ActiveRecord::Base
      scope :with_name_like, lambda { |x| where("name LIKE '%#{x}%'") }
      scope :with_status_value, lambda { |x| where(status: x)}
    end

    build_model_table(NoEnum,name: :string, status: :integer)
    NoEnum.create(name: "item 1", status: 1)
    NoEnum.create(name: "item 2", status: 2)
    NoEnum.create(name: "item 1.1", status: 1)

  end
  
  describe "model setup" do
    it "should have created 10 users" do 
      expect(User.count).to eq(10)
    end
    it "should have created 4 books" do
      expect(Book.count).to eq(4)
    end
    it "should have 3 created NoEnum objects" do
      expect(NoEnum.count).to eq(3)
    end
  end
  
  describe "When asigning to an enumed attribute " do
    it "should only accept valid values " do
      expect { User.new status: :condition }.to raise_error
      expect { User.new status: :active}.not_to raise_error
    end
    
    it "should set the encoded enum value to the attribute" do
      u = User.new status: :active
      expect(u.read_attribute :status).to eq("active")
      b = Book.new condition: :used
      expect(b.read_attribute :condition).to eq(1)
    end
    
    it "should be able to use the DB value directly rather than the symbolic code" do
      u = User.new status: "active"
      expect(u.status).to eq(:active)
      b = Book.new condition: 1
      expect(b.condition).to eq(:used)
    end
    
    it "should be able to check the attributes value via is_<value>? form for primary keys" do
      u = User.new status: "active"
      expect(u.is_active?).to be true
      expect(u.is_suspended?).to be false
      expect(u.is_terminated?).to be false
      b = Book.new condition: 1
      expect(b.is_used?).to be true
      expect(b.is_mint?).to be false
    end
    
    it "should be able to check the attributes value via is_<value>? form for non-primary keys" do
      u = User.new role: "customer"
      expect(u.is_role_customer?).to be true
      expect(u.is_role_supplier?).to be false
    end
  end
  
  describe "scoped querying for primary enums" do
    it "should create a relation" do
      expect(User.active.is_a?(ActiveRecord::Relation)).to be true
    end
    it "should return valid records where the attribute matches the scoped enum value " do
      expect(User.active.length).to eq(3)
      expect(User.suspended.length).to eq(2)
      expect(User.registration_pending.length).to eq(4)
      expect(User.not_active.sort_by(&:id)).to eq((User.registration_pending + User.suspended + User.terminated).sort_by(&:id))
      expect((User.not_active + User.active).sort_by(&:id)).to eq(User.all)
    end
    it "should return the correct count where attribute matches the scoped enum value " do
      expect(User.active.count).to eq(3)
    end
  end
  
  describe "scoped querying for non-primary enums" do
    it "should support (attribute-name)_value and (attribute-name)_not_value nomenclature" do
      expect(User.role_customer.length).to eq(8)
      expect(User.role_not_customer.length).to eq(2)   
    end
  end
  
  describe "scoped querying" do
    it "should support has_many subclasses" do
      expect(User.first.books.mint.length).to eq(2)
      expect(User.first.books.used.length).to eq(1)      
    end
    it "should support compound scopes on a single class" do 
      expect(User.active.role_customer.length).to eq(3)
      expect(User.not_active.role_customer.length).to eq(5)
      expect(User.active.role_supplier.length).to eq(0)
    end
    it "should play nice with predefined scopes that don't use enums" do 
      expect(User.with_name_like("Joe").length).to eq(6)
    end
    it "should play nice with predefined scopes that use enums" do 
      expect(User.role_supplier.with_name_like("Joe").length).to eq(2)
      expect(User.with_name_like("Joe").role_supplier.length).to eq(2)
    end

  end
  
  describe "to find valid enum values " do
    it "should return an array of valid values when class is sent message with attribute name" do
      expect(User.roles).to eq([:customer,:supplier])
      expect(Book.conditions.sort).to eq([:mint,:used,:excellent, :almost_new].sort)
      expect(Book.choices_list(:condition).sort).to eq([:mint,:used,:excellent, :almost_new].sort)
    end
    it "should return the set values if asked" do
      # expect(Book.conditions(set: :primo).sort).to eq([:mint,:excellent,:almost_new].sort)
      # expect(User.statuses(set: :inactive).sort).to eq([:suspended,:terminated,:registration_pending].sort)
    end
  end

  describe "where queries" do
    it "should substitute value for symoblic code in hash predicates" do
      expect(User.where(status: :active).length).to eq(3)
      expect(User.where(status: :active).to_sql).to match /status["'\\ ]*=["'\\ ]*active/
      expect(Book.where(condition: :used).to_sql).to match /condition["'\\ ]*=["'\\ ]*1/
      expect(Book.where(condition: :almost_new).to_sql).to match /condition["'\\ ]*=["'\\ ]*3/
      expect(User.where(status: :registration_pending).to_sql).to match /status["'\\ ]*=["'\\ ]*registration pending/
    end
    it "should substitute value for symoblic code in array predicates" do
      expect(User.where(["status = ?",:active]).length).to eq(3)
      expect(User.where(["status = ?",:active]).to_sql).to match /status["'\\ ]*=["'\\ ]*active/
      expect(Book.where(["condition = ?",:used]).to_sql).to match /condition["'\\ ]*=["'\\ ]*1/
    end
    it "should handle arrays of enum values" do
      expect(User.where(status: [:active,:terminated]).count).to eq(4)
      expect(User.where(status: [:active,:terminated])).to eq(User.active + User.terminated)
    end
  end
  
  describe  "With sets" do
    it "should not be possible to assign a set value to the attribute" do
      expect{ User.new status: :inactive}.to raise_error
    end
    it "should be possible to reference a scoped set value and return all inclusive set value records" do
      expect(User.inactive - (User.suspended + User.terminated + User.registration_pending)).to eq([])
    end
    it "should be possible to create compound scopes" do
      expect(User.inactive.role_customer.length).to eq(5)
    end

    it "should be possible to use sets in where clauses" do
      expect(User.where(status: :inactive).sort_by(&:id)).to eq((User.suspended + User.terminated + User.registration_pending ).sort_by(&:id))
      expect(User.where(status: :inactive).count).to eq(7)
      expect(User.where(["status = ?",:inactive]).sort_by(&:id)).to eq(User.inactive.sort_by(&:id))
    end
    it "should be possible to negate set value" do
      expect(User.not_inactive.map(&:id)).to eq(User.active.map(&:id))
    end
    it "should be possible to see if a value matches if it's part of a set" do
      expect(User.enum_matches?(:status,:suspended,:inactive)).to be true
      expect(User.enum_matches?(:status,:terminated,:inactive)).to be true
      expect(User.enum_matches?(:status,:active,:inactive)).to be false
    end

    it "should be possible to query subclasses with values of sets" do
      expect(User.first.books.used.count).to eq(1)
      expect(User.first.books.primo.count).to eq(3)
    end
  end

  describe "When attribute is not enum'ed" do
    it "should behave as if enum_handler not there" do
      expect(User.db_code(:name,"fred")).to eq("fred")
    end
  end

  describe "a class without enum_handler" do
    it "should return correct results with all query" do
      expect(NoEnum.count).to eq(3)
      expect(NoEnum.all.length).to eq(3)
    end
    it "should return correct results with where query with hash predicate" do
      expect(NoEnum.where(status: 2).length).to eq(1)
      expect(NoEnum.where(status: 3).length).to eq(0)
      expect(NoEnum.where(status: 1).length).to eq(2)
      expect(NoEnum.where(name: "item 1").length).to eq(1)
      expect(NoEnum.where(name: "item 1",status: 1).length).to eq(1)
      expect(NoEnum.where(name: "item 1",status: 0).length).to eq(0)
    end
    it "should return correct results with where query with array predicate" do
      expect(NoEnum.where(["status = ?", 2]).length).to eq(1)
      expect(NoEnum.where(["status = ?", 3]).length).to eq(0)
      expect(NoEnum.where(["status = ?", 1]).length).to eq(2)
      expect(NoEnum.where(["name = ?","item 1"]).length).to eq(1)
      expect(NoEnum.where(["name = ? and status = ?","item 1",1]).length).to eq(1)
      expect(NoEnum.where(["name = ? and status = ?","item 1",0]).length).to eq(0)
    end
    it "should return correct results with scopes" do
      expect(NoEnum.with_name_like("1").length).to eq(2)
      expect(NoEnum.with_name_like("1").count).to eq(2)
      expect(NoEnum.with_status_value(1).length).to eq(2)
      expect(NoEnum.with_status_value(2).length).to eq(1)
    end
  end

end
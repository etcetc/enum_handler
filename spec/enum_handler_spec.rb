require 'spec_helper'
describe "EnumHandler" do
  before(:all) do 
    # Create the models
    class Book < ActiveRecord::Base
      include EnumHandler
      define_enum :condition, {mint: 0,used: 1,excellent: 2}, primary:true, sets: {primo: [:mint,:excellent]}
    end
    build_model_table(Book,condition: :integer,user_id: :integer)
    class User < ActiveRecord::Base
      include EnumHandler
      has_many :books
      define_enum :status, [:active,:suspended,:terminated], primary: true, sets:{inactive: [:suspended,:terminated]}
      define_enum :role, [:customer,:supplier]
    end
    build_model_table(User,status: :string, role: :string)
    3.times { User.create(status: :active, role: :customer) }
    2.times { User.create(status: :suspended, role: :supplier) }
    1.times { User.create(status: :terminated, role: :customer) }
    User.first.books << Book.create(condition: :mint)
    User.first.books << Book.create(condition: :mint)
    User.first.books << Book.create(condition: :used)
  end
  
  describe "model setup" do
    it "should have created 6 users" do 
      expect(User.count).to  eq(6)
    end    
  end
  
  describe "When asigning to an enum " do
    it "only valid values should be accepted" do
      expect { User.new status: :condition }.to raise_error
      expect { User.new status: :active}.not_to raise_error
    end
    
    it "underlying attribute value should match the encoded enum value" do
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
    it "based upon enum values should return valid values" do
      expect(User.active.length).to eq(3)
      expect(User.suspended.length).to eq(2)
      expect(User.not_active.length).to eq(3)
    end
    it "for count based upon enum values should return valid values " do
      expect(User.active.count).to eq(3)
    end
  end
  
  describe "scoped querying for non-primary enums" do
    it "should support (attribute-name)_value and (attribute-name)_not_value nomenclature" do
      expect(User.role_customer.length).to eq(4)
      expect(User.role_not_customer.length).to eq(2)   
    end
  end
  
  describe "scoped querying" do
    it "should support has_many subclasses" do
      expect(User.first.books.mint.length).to eq(2)
      expect(User.first.books.used.length).to eq(1)      
    end
  end
  
  describe "where queries" do
    it "should substitute value for symoblic code in hash predicates" do
      expect(User.where(status: :active).length).to eq(3)
      expect(User.where(status: :active).to_sql).to match /status["'\\ ]*=["'\\ ]*active/
      expect(Book.where(condition: :used).to_sql).to match /condition["'\\ ]*=["'\\ ]*1/
    end
    it "should substitute value for symoblic code in array predicates" do
      expect(User.where(["status = ?",:active]).length).to eq(3)
      expect(User.where(["status = ?",:active]).to_sql).to match /status["'\\ ]*=["'\\ ]*active/
      expect(Book.where(["condition = ?",:used]).to_sql).to match /condition["'\\ ]*=["'\\ ]*1/
    end
  end
  
  describe  "With sets" do
    it "should not be possible to assign a set value to the attribute" do
      expect{ User.new status: :inactive}.to raise_error
    end
    it "should be able to reference a scoped set value and return all inclusive set value records" do
      expect(User.inactive).to eq(User.suspended + User.terminated )
    end
    it "should be able to use sets in where clauses" do
      expect(User.where(status: :inactive)).to eq(User.suspended + User.terminated )
      expect(User.where(["status = ?",:inactive])).to eq(User.suspended + User.terminated )
    end
    it "should be able to negate set value" do
      expect(User.not_inactive.map(&:id)).to eq(User.active.map(&:id))
    end
  end
end
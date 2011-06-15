require File.dirname(__FILE__) + '/../../spec_helper'

module Card  
  class CardtypeA < Basic  
    def approve_delete 
      deny_because("not allowed to delete card a")
    end
  end

  class CardtypeB < Basic                              
    # create restricted in test_data
  end
  
  class CardtypeC < Basic
    def validate_type_change
      errors.add :destroy_error, "card c is indestructible"
    end
  end
  
  class CardtypeD < Basic 
    def valid?
      errors.add :create_error, "card d always has errors"
    end
  end
  
  class CardtypeE < Basic           
    cattr_accessor :count
    @@count = 2
    def on_type_change
      decrement_count
    end
    def decrement_count() self.class.count -= 1; end
  end
  
  class CardtypeF < Basic
    cattr_accessor :count
    @@count = 2
    before_validation_on_create :increment_count
    def increment_count() self.class.count += 1; end
  end

end   



describe Card, "with role" do
  before do
    User.as :wagbot 
    @role = Card::Role.find(:first)
  end
  
  it "should have a role extension" do
    @role.extension_type.should=='Role'
  end

  it "should lose role extension upon changing type" do
    # this test fails on a permission error in Mysql
    pending
    @role.type = 'Basic'
    @role.save
    @role.extension.should == nil
  end
end



describe Card, "with account" do
  before do
    User.as :wagbot 
    @joe = change_card_to_type('Joe User', 'Basic')
  end
  
  it "should not have errors" do
    @joe.errors.empty?.should == true
  end

  it "should allow type changes" do
    @joe.type.should == 'Basic'
  end


  it "should not lose account on card change" do
    @joe.extension.should_not == nil
  end
end



describe Card, "type transition approve create" do
  before do
    Card.create :name=>'Cardtype B+*type+*create', :type=>'Pointer', :content=>'[[r1]]'
  end
  
  it "should have errors" do
    lambda { change_card_to_type("basicname", "CardtypeB") }.should raise_error(Wagn::PermissionDenied)
  end

  it "should be the original type" do
    lambda { change_card_to_type("basicname", "CardtypeB") }
    Card.find_by_name("basicname").type.should == 'Basic'
  end
end



describe Card, "clone to type"  do
  before do
    User.as :wagbot 
    @a = Card.find_by_name("basicname")
    @b = @a.send(:clone_to_type, "CardtypeA") 
  end  
  
  it "should have the new type" do
    @b.type.should == 'CardtypeA'
    @b.class.should == Card::CardtypeA
  end
  
  it "should have the same id" do
    @b.id.should == @a.id
  end 
  
  it "should not be a new record" do
    @b.new_record?.should == false
  end
end

=begin  - NOT currently checking delete permissions on card type change                  
describe Card, "type transition approve type" do
  it "should have errors" do
    lambda {change_card_to_type("type-a-card", "Basic")}.should raise_error(Wagn::PermissionDenied)
  end
              
  it "should still be the original type" do
    change_card_to_type("type-a-card", "Basic")
    Card.find_by_name("type-a-card").type.should == 'CardtypeA'
  end
end
=end

describe Card, "type transition validate_destroy" do  
  before do @c = change_card_to_type("type-c-card", 'Basic') end
  
  it "should have errors" do
    @c.errors.on(:destroy_error).should == "card c is indestructible"
  end
  
  it "should retain original type" do
    Card.find_by_name("type_c_card").type.should == 'CardtypeC'
  end
end

describe Card, "type transition validate_create" do
  before do @c = change_card_to_type("basicname", "CardtypeD") end
  
  it "should have errors" do
    @c.errors.on(:create_error).should == "card d always has errors"
  end
  
  it "should retain original type" do
    Card.find_by_name("basicname").type.should == 'Basic'
  end
end

describe Card, "type transition destroy callback" do
  before do
    Card::CardtypeE.count = 2
    @c = change_card_to_type("type-e-card", "Basic") 
  end
  
  it "should decrement counter in before destroy" do
    Card::CardtypeE.count.should == 1
  end
  
  it "should change type of the card" do
    Card.find_by_name("type-e-card").type.should == 'Basic'
  end
end

describe Card, "type transition create callback" do
  before do 
    Card.create(:name=>'Basic+*type+*delete', :type=>'Pointer', :content=>"[[Anyone Signed in]]")
    Card::CardtypeF.count = 2
    @c = change_card_to_type("basicname", 'CardtypeF') 
  end
    
  it "should increment counter"  do
    Card::CardtypeF.count.should == 3
  end
  
  it "should change type of card" do
    Card.find_by_name("basicname").type.should == 'CardtypeF'
  end
end                


def change_card_to_type(name, type)
  User.as :joe_user do
    card = Card.fetch(name)
    warn "#{card.name} already exists.  current type = #{card.type} changing to type: #{type}"
    card.type = type;  
    card.save
    card
  end
end




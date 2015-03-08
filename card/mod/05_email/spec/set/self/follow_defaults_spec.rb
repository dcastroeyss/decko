# -*- encoding : utf-8 -*-

describe Card::Set::Self::FollowDefaults do
  context 'when updated' do
    before do 
      Card::Auth.as_bot do
        ca = Card[:follow_defaults]
        ca.update_attributes! :content=>'[[A+*self+*always]]'
      end
    end
    it 'updates follow rules of users' do
      ca = Card.fetch 'A'
      expect(ca.follower_names).to include "Joe User"
    end
  end
end
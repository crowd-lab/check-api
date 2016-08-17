require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class TeamUserTest < ActiveSupport::TestCase
  test "should create team user" do
    assert_difference 'TeamUser.count' do
      create_team_user
    end
  end

  test "should prevent creating team user with invalid status" do
    tu = create_team_user
    tu.status = "invalid status"
    assert_not tu.save
    tu.status = "banned"
    assert tu.save
  end

  test "should get user from callback" do
    u = create_user email: 'test@local.com'
    tu = create_team_user
    assert_equal u.id, tu.user_id_callback('test@local.com')
  end

  test "should get team from callback" do
    tu = create_team_user
    assert_equal 2, tu.team_id_callback(1, [1, 2, 3])
  end
end

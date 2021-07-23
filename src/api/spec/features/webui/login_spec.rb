require 'browser_helper'
require 'ldap'

RSpec.describe 'Login', type: :feature, js: true do
  let!(:user) { create(:confirmed_user, :with_home, login: 'proxy_user') }
  let(:admin) { create(:admin_user) }

  it 'login with home project shows a link to it' do
    login user
    expect(page).to have_link('Your Home Project', visible: :all)
  end

  it 'login without home project shows a link to create it' do
    login admin
    user.home_project.destroy
    login user
    expect(page).to have_link('Create Your Home Project', visible: :all)
  end

  it 'login via login page' do
    visit new_session_path

    within('#loginform') do
      fill_in 'username', with: user.login
      fill_in 'password', with: 'buildservice'
      click_button('Log In')
    end

    expect(page).to have_link('Profile', visible: :all)
  end

  it 'login via widget' do
    visit root_path
    within(desktop? ? '#top-navigation-area' : '#bottom-navigation-area') do
      click_link('Log In')
    end

    within('#log-in-modal') do
      fill_in 'username', with: user.login
      fill_in 'password', with: 'buildservice'
      click_button('Log In')
    end

    expect(page).to have_link('Your Home Project', visible: :all)
  end

  it 'login with wrong data' do
    visit root_path
    within(desktop? ? '#top-navigation-area' : '#bottom-navigation-area') do
      click_link('Log In')
    end

    within('#log-in-modal') do
      fill_in 'username', with: user.login
      fill_in 'password', with: 'foo'
      click_button('Log In')
    end

    expect(page).to have_content('Authentication failed')
  end

  it 'logout' do
    login(user)

    if desktop?
      click_link(id: 'top-navigation-profile-dropdown')
      within('#top-navigation-area') do
        click_link('Logout')
      end
    else
      click_menu_link('Places', 'Logout')
    end

    expect(page).not_to have_css('a#link-to-user-home')
    expect(page).to have_link('Log')
  end

  context 'in ldap mode' do
    include_context 'setup ldap mock with user mock'
    include_context 'an ldap connection'

    let(:ldap_user) { double(:ldap_user, to_hash: { 'dn' => 'tux', 'sn' => ['John', 'Smith'] }) }

    before do
      stub_const('CONFIG', CONFIG.merge('ldap_mode' => :on,
                                        'ldap_search_user' => 'tux',
                                        'ldap_search_auth' => 'tux_password',
                                        'ldap_ssl' => :off,
                                        'ldap_authenticate' => :ldap))

      allow(ldap_mock).to receive(:search).and_yield(ldap_user)
      allow(ldap_mock).to receive(:unbind)

      allow(ldap_user_mock).to receive(:bind).with('tux', 'tux_password')
      allow(ldap_user_mock).to receive(:bound?).and_return(true)
      allow(ldap_user_mock).to receive(:search).and_yield(ldap_user)
      allow(ldap_user_mock).to receive(:unbind)
    end

    it 'allows the user to login via the webui' do
      visit new_session_path

      within('#loginform') do
        fill_in 'username', with: 'tux'
        fill_in 'password', with: 'tux_password'
        click_button('Log In')
      end

      expect(page).to have_link('Profile', visible: :all)
      expect(page).to have_link('Logout', visible: :all)
    end
  end
end

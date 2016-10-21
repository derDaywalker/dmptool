class User < ActiveRecord::Base

  include UserEmail

  before_create :set_auth_token #used for api token-based authentication

  acts_as_paranoid

  serialize :prefs, Hash

  belongs_to :institution
  has_many :user_plans
  has_many :plans, through: :user_plans
  has_many :comments
  has_many :authentications, autosave: true, dependent: :destroy
  has_many :authorizations
  has_many :roles, through: :authorizations

  has_many :owned_plans, -> { where user_plans: { owner: true} }, through: :user_plans,
  source: :plan, class_name: 'Plan'

  has_many :coowned_plans, -> { where user_plans: { owner: false} }, through: :user_plans,
  source: :plan, class_name: 'Plan'

  scope :active, -> { where(active: true, deleted_at: nil) }

  accepts_nested_attributes_for :user_plans

  attr_accessor :ldap_create, :password, :password_confirmation, :skip_email_uniqueness_validation

  VALID_EMAIL_REGEX = /\A[^@]+@[^@]+\.[^@]+\z/i #very simple, but requires basic format and emails are nearly impossible to validate anyway
  validates :institution_id, presence: true, numericality: true
  validates :email, presence: true
  validates :email, uniqueness: true unless :skip_email_uniqueness_validation
  validates_format_of :email, with: VALID_EMAIL_REGEX, :allow_blank => true
  validates :prefs, presence: true
  validates :login_id, presence: true, uniqueness: { case_sensitive: false }, :if => :ldap_create
  validates_presence_of :password, :password_confirmation,  on: :create
  validates_presence_of :first_name
  validates_presence_of :last_name
  validates_confirmation_of :password
  #validates_format_of :orcid_id, with: /[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}/, :allow_blank => true
  validates_format_of :password, with: /([A-Za-z])/, :allow_blank => true
  validates_format_of :password, with: /([0-9])/, :allow_blank => true
  validates_length_of :password, within: 8..30, :allow_blank => true

  before_validation :default_preferences, if: Proc.new { |x| x.prefs.empty? }
  before_validation :add_default_institution, if: Proc.new { |x| x.institution_id.nil? }

  before_update :try_update_ldap, :if => :email_changed?

  after_destroy :make_other_tables_consistent


  class LoginException < Exception ; end

  def ensure_ldap_authentication(uid)
    unless Authentication.find_by_user_id_and_provider(self.id, 'ldap')
      Authentication.create(:user => self, :provider => 'ldap', :uid => uid)
    end
  end

  ##
  # Returns both the user and its corresponding authentication object for the
  # _auth_ info and _institution_id_. If the records do not already exist in the
  # database, valid, but unsaved, instances are returned.

  def self.from_omniauth(auth, institution_id)
    auth = auth.with_indifferent_access
    info = auth[:info] = auth[:info].with_indifferent_access unless auth[:info].blank?

    uid = smart_userid_from_omniauth(auth) #gets info[:uid] or auth[:uid], reduced long LDAP string to simple user_id
    email = smart_email_from_omniauth(info.try(:[], :email))

    fail LoginException, 'incomplete information from identity provider' unless uid && email

    # The following two lines are scary.
    # In User#create, email uniqueness validation is turned off, which is
    # probably the reason why we have them here. Anyway, I couldn't find out if
    # it really matters, therefore I'm not touching that.
    u = User.with_deleted.where(email: email)

    raise LoginException.new('multiple users with same email') if u.length > 1

    # Not sure why we have this. user_sessions#create already validates if
    # users are active, thus this code is probably redundant.
    raise LoginException.new('user deactivated') if u.length == 1 && (!u.first.deleted_at.blank? || u.active == false)

    a = Authentication.find_or_initialize_by(uid: uid, provider: auth[:provider])
    if a.new_record?
      a.user = User.find_or_initialize_by(email: email)

      if a.user.new_record?
        a.user.attributes = {
          login_id: uid,
          first_name: info.try(:[], :first_name),
          last_name: info.try(:[], :last_name),
          institution_id: institution_id,
          prefs: default_preferences
        }
      elsif auth[:provider] == :shibboleth
        a.user.institution_id = institution_id
      end
    else
      raise LoginException.new('authentication without user record') if a.user.nil?
    end

    return a.user, a
  end

  #returns the userid from omniauth.  May be long string for shibboleth
  # but for ldap we only get a brief username without all the uid, ou, ou, etc
  def self.smart_userid_from_omniauth(auth)
    info = auth[:info]
    uid = (info ? info[:uid] : nil) || auth[:uid]
    
    if uid.match(/^uid=\S+?,ou=\S+?,ou=\S+?,dc=\S+?,dc=\S+?$/)
      return uid.match(/^uid=(\S+?),ou=\S+?,ou=\S+?,dc=\S+?,dc=\S+?$/)[1]
    end

    # If there are multiple uids present, just take the first one
    matches = uid.match(/(^.*?)[;,]/i)
    if matches
      uid = matches[1]
    end
    
    uid
  end

  #fixes weird emails, only gets first email and dumps garbage like ;, or
  #multiple emails incorrectly jammed into one field
  def self.smart_email_from_omniauth(email)
    e = email
    if email.class == Array
      e = email.first
    end
    matches = e.match(/(^.*?)[;,]/i)
    if matches
      e = matches[1]
    end
    e
  end

  def self.search_terms(terms)
    items = terms.split
    conditions1 = items.map{|item| "CONCAT(first_name, ' ', last_name) LIKE ?" }
    conditions2 = items.map{|item| "email LIKE ?" }
    conditions = "( (#{conditions1.join(' AND ')})" + ' OR ' + "(#{conditions2.join(' AND ')}) )"
    values = items.map{|item| "%#{item}%" }
    self.where(conditions, *(values * 2) )
  end

  def full_name
    [first_name, last_name].join(" ")
  end

  def full_name_last_first
    [last_name, first_name].join(" ")
  end


  #label for dropdown for autocomplete
  def label
    "#{self.full_name} <#{self.email}>"
  end

  def plans_by_state(state)
    #get all plans this user has in the state specified
    Plan.joins(:current_state, :user_plans).
          where(:user_plans => { :user_id => self.id }).
          where(:plan_states => { :state => state})
  end

  def unique_plan_states
    #returns a list of the unique plan states that this user has
    Plan.joins(:current_state, :user_plans).
        where(:user_plans => { :user_id => self.id }).
        select('plan_states.state').distinct.pluck(:state)
  end

  def role_ids
    @role_id ||= self.authorizations.pluck(:role_id) #caches role ids
  end


  def has_any_role?
    self.authorizations.count > 0
  end

  def role_names
    @role_names ||= self.roles.pluck(:name)
  end

  

  def has_role?(role_id)
    role_ids.include?(role_id)
  end

  def has_role_name?(role_name)
    role_names.include?(role_name)
  end

  #this takes an array of numeric role ids and will update that user to have those role ids by deleting and adding as needed
  def update_authorizations(role_ids)
    role_ids = role_ids.map {|i| i.to_i }
    roles = self.roles.collect(&:id) # get current role ids
    roles_to_remove = roles - role_ids
    roles_to_add = role_ids - roles

    unless roles_to_remove.blank?
      self.authorizations.where(role_id: roles_to_remove).destroy_all
    end

    unless roles_to_add.blank?
      roles_to_add.each do |r|
        self.authorizations.create({:role_id => r})
      end
      email_roles_granted(roles_to_add)
    end
    return {:roles_added => roles_to_add, :roles_removed => roles_to_remove}
  end



  #used for api token-based authentication
  def set_auth_token
    return if auth_token.present?
    self.auth_token = generate_auth_token
  end


  #used for api token-based authentication
  def generate_auth_token
    loop do 
      token = SecureRandom.hex
      break token unless self.class.exists?(auth_token: token)
    end
  end

  def created
    created_at.to_date.strftime("%m/%d/%Y")
  end

  def modified
    updated_at.to_date.strftime("%m/%d/%Y")
  end

  
  private


  

  def add_default_institution
    self.institution_id = 0
  end

  def default_preferences
    self.prefs = self.class.default_preferences
  end

  def self.default_preferences
    {
        users:                   {
            role_granted: true
        },
        dmp_owners_and_co:       {
            new_comment: true,
            committed:    true,
            vis_change:   true,
            submitted:   true,
            user_added:  true
        },
        requirement_editors:     {
            committed:  true,
            deactived: true
        },
        resource_editors:        {
            deleted:             true,
            associated_committed: true
        },
        institutional_reviewers: {
            submitted:         true,
            new_comment:       true,
            approved_rejected: true
        }
    }

  end

  def secure_hash(string)
    Digest::SHA2.hexdigest(string)
  end

  public

  

  #sets a new token if it's not set or is expired
  def ensure_token
    if self.token_expiration and Time.now > self.token_expiration
      self.token = nil
    end
    self.token ||= self.generate_token
    self.token_expiration = Time.now + 1.day
    self.save
    return self.token
  end

  def clear_token
    self.token = nil
    self.token_expiration = nil
    self.save
  end

  def ldap_user?
    self.authentications.where(:provider => 'ldap').first.present?
  end

  #anytime the email is updated, try to update ldap or return false to prevent saving when it can't be changed
  def try_update_ldap
    auths = self.authentications.where(provider: 'shibboleth')
    return false if auths.length > 0

    auths = self.authentications.where(provider: 'ldap')
    if auths.length > 0
      uid = auths.first.uid
    else
      uid = self.login_id
    end
    begin
      Ldap_User::LDAP.replace_attribute(uid, 'mail', [self.email])
    rescue LdapMixin::LdapException => ex
      return false
    end
    return true
  end

  protected

  TOKEN_CHARS = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
  def generate_token
    40.times.collect {TOKEN_CHARS.sample}.join('')
  end

  def make_other_tables_consistent
    Authentication.destroy_all(user_id: self.id)
    Authorization.destroy_all(user_id: self.id)
  end
end

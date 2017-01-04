class Media < ActiveRecord::Base
  attr_accessible
  attr_accessor :project_id, :duplicated_of, :project_object

  has_paper_trail on: [:create, :update]
  belongs_to :account
  belongs_to :user
  has_many :project_medias
  has_many :projects, through: :project_medias
  has_annotations

  include PenderData

  validate :validate_pender_result, on: :create
  validate :pender_result_is_an_item, on: :create
  validate :url_is_unique, on: :create
  validate :validate_quote_for_media_with_empty_url, on: :create

  before_validation :set_url_nil_if_empty, :set_user, on: :create
  after_create :set_pender_result_as_annotation, :set_project, :set_account
  after_rollback :duplicate

  def current_team
    self.project.team if self.project
  end

  def user_id_callback(value, _mapping_ids = nil)
    user_callback(value)
  end

  def account_id_callback(value, mapping_ids)
    mapping_ids[value]
  end

  def pm_dbid(context)
    pm = self.project_medias.find_by(:project_id => context.id) unless context.nil?
    pm.nil? ? 0 : pm.id
  end

  def project_media(context = nil)
    context = self.get_media_context(context)
    self.project_medias.find_by(:project_id => context.id) unless context.nil?
  end

  def get_team
    self.projects.map(&:team_id)
  end

  def get_team_objects
    self.projects.map(&:team)
  end

  def associate_to_project
    if !self.project_id.blank? && !ProjectMedia.where(project_id: self.project_id, media_id: self.id).exists?
      pm = ProjectMedia.new
      pm.project_id = self.project_id
      pm.media = self
      pm.user = pm.current_user = self.current_user
      pm.context_team = self.context_team
      pm.save!
    end
  end

  def relay_id
    str = "Media/#{self.id}"
    str += "/#{self.project_id}" unless self.project_id.nil?
    Base64.encode64(str)
  end

  def get_media_context(context = nil)
    context.nil? ? self.project : context
  end

  def domain
    host = URI.parse(self.url).host unless self.url.nil?
    host.nil? ? nil : host.gsub(/^(www|m)\./, '')
  end

  def project
    return self.project_object unless self.project_object.nil?
    if self.project_id
      Rails.cache.fetch("project_#{self.project_id}", expires_in: 30.seconds) do
        Project.find(self.project_id)
      end
    end
  end

  def overriden_embed_attributes
    %W(title description username quote)
  end

  private

  def set_url_nil_if_empty
    self.url = nil if self.url.blank?
  end

  def set_user
    self.user = self.current_user unless self.current_user.nil?
  end

  def set_account
    unless self.pender_data.nil?
      account = Account.new
      account.url = self.pender_data['author_url']
      if account.save
        self.account = account
      else
        self.account = Account.where(url: account.url).last
      end
      self.save!
    end
  end

  def pender_result_is_an_item
    unless self.pender_data.nil?
      errors.add(:base, 'Sorry, this is not a valid media item') unless self.pender_data['type'] == 'item'
    end
  end

  def url_is_unique
    unless self.url.nil?
      existing = Media.where(url: self.url).first
      self.duplicated_of = existing
      errors.add(:base, "Media with this URL exists and has id #{existing.id}") unless existing.nil?
    end
  end

  def validate_quote_for_media_with_empty_url
      if self.url.blank? and self.quote.blank?
        errors.add(:base, "quote can't be blank")
      end
  end

  def set_project
    self.associate_to_project
  end

  def duplicate
    dup = self.duplicated_of
    unless dup.blank?
      dup.project_id = self.project_id
      dup.context_team = self.context_team
      dup.current_user = self.current_user
      dup.origin = self.origin
      dup.associate_to_project
      return false
    end
    true
  end
end

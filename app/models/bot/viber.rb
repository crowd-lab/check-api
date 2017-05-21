class Bot::Viber < ActiveRecord::Base
  def self.default
    Bot::Viber.where(name: 'Viber Bot').last
  end

  def text_to_image(m)
    av = ActionView::Base.new(Rails.root.join('app', 'views'))
    av.assign(m)
    content = av.render(template: 'viber/screenshot.html.erb', layout: nil)
    filename = 'screenshot-' + Digest::MD5.hexdigest(m.inspect)
    html_path = File.join(Rails.root, 'public', 'viber', filename + '.html')
    image_path = File.join(Rails.root, 'public', 'viber', filename + '.jpg')
    File.atomic_write(html_path) do |file|
      file.write(content)
    end
  
    url = CONFIG['checkdesk_base_url_private'] + '/viber/' + filename + '.html'
    screenshoter = File.join(Rails.root, 'bin', 'take-screenshot.js')
    system 'nodejs', screenshoter, "--url=#{url}", "--output=#{image_path}", "--delay=3"
    system 'convert', Shellwords.escape(image_path), '-trim', '-strip', '-quality', '90', Shellwords.escape(image_path)
    FileUtils.rm_f html_path
    filename
  end

  def send_message(body)
    uri = URI('https://chatapi.viber.com/pa/send_message')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    req['X-Viber-Auth-Token'] = CONFIG['viber_token']
    req.body = body
    http.request(req)
  end

  def sender
    { name: 'Bridge', avatar: CONFIG['checkdesk_base_url'] + '/images/bridge.png' }
  end

  def send_text_message(user_id, text)
    body = { receiver: user_id, sender: self.sender, type: 'text', text: text }.to_json
    self.send_message(body)
  end

  def send_image_message(user_id, image)
    body = { receiver: user_id, sender: self.sender, type: 'picture', text: '', media: image }.to_json
    self.send_message(body)
  end

  DynamicAnnotation::Field.class_eval do
    include CheckElasticSearch
    
    validate :translation_status_is_valid
    validate :can_set_translation_status
    validate :translation_request_id_is_unique, on: :create

    after_update :respond_to_user
    after_save :update_elasticsearch_status

    attr_accessor :previous_status, :disable_es_callbacks

    def previous_value
      self.value_was.nil? ? self.value : self.value_was
    end

    def status
      self.value if self.field_name == 'translation_status_status'
    end

    def status=(value)
      if self.field_name == 'translation_status_status'
        self.value = value
      end
    end

    protected

    def cant_change_status(user, options, from_status, to_status)
      !user.nil? && !options[to_status].blank? && !user.is_admin? && (!user.role?(options[to_status]) || !user.role?(options[from_status]))
    end

    def store_approver
      if self.field_name == 'translation_status_status' && self.value == 'ready' && User.current.present?
        url = begin
                User.current.accounts.first.url
              rescue
                nil
              end

        annotation = self.annotation.load
        annotation.set_fields = { translation_status_approver: { name: User.current.name, url: url }.to_json }.to_json 
        annotation.save!
      end
    end

    def should_respond_to_user?
      self.field_name == 'translation_status_status' && self.previous_status.to_s != self.value.to_s
    end

    private

    def update_elasticsearch_status
      if self.field_name == 'translation_status_status'
        self.update_media_search(['status'], { 'status' => self.value }, self.annotation.annotated_id)
      end
    end

    def translation_status_is_valid
      if self.field_name == 'translation_status_status'
        options = self.field_instance.settings[:options_and_roles]
        value = self.value.to_sym

        errors.add(:base, I18n.t(:translation_status_not_valid, default: 'Status not valid')) unless options.keys.include?(value)
      end
    end

    def can_set_translation_status
      if self.field_name == 'translation_status_status'
        options = self.field_instance.settings[:options_and_roles]
        value = self.value.to_sym
        old_value = self.previous_value.to_sym
        self.previous_status = old_value
        user = User.current

        if self.cant_change_status(user, options, old_value, value)
          errors.add(:base, I18n.t(:translation_status_permission_error, default: 'You are not allowed to make this status change'))
        end
      end
    end

    def respond_to_user
      if self.should_respond_to_user?
        request = self.annotation.annotated.get_dynamic_annotation('translation_request')
        if self.value == 'ready'
          self.store_approver
          translation = self.annotation.annotated.get_dynamic_annotation('translation')
          Bot::Twitter.default.send_to_twitter_in_background(translation)
          Bot::Facebook.default.send_to_facebook_in_background(translation)
          request.respond_to_user(true) unless request.nil?
        end
        request.respond_to_user(false) if self.value == 'error' && !request.nil?
      end
    end

    def translation_request_id_is_unique
      if self.field_name == 'translation_request_id' &&
         DynamicAnnotation::Field.where(field_name: 'translation_request_id', value: self.value).exists?
        errors.add(:base, I18n.t(:translation_request_id_exists, default: 'There is already a translation request for this message'))
      end
    end
  end

  Dynamic.class_eval do
    before_validation :store_previous_status

    def translation_status
      self.get_field('translation_status_status').to_s if self.annotation_type == 'translation_status'
    end

    def previous_translation_status
      @previous_translation_status
    end

    def previous_translation_status=(status)
      @previous_translation_status = status
    end

    def from_language(locale = 'en')
      if self.annotation_type == 'translation'
        lang = nil
        begin
          lang = CheckCldr.language_code_to_name(self.annotated.get_dynamic_annotation('language').get_field('language').value, locale)
        rescue
          lang = nil
        end
        lang
      end
    end

    def translation_to_message
      if self.annotation_type == 'translation'
        begin
          viber_user_locale = nil
          begin
            viber_user_locale = JSON.parse(self.annotated.get_dynamic_annotation('translation_request').get_field_value('translation_request_raw_data'))['originalRequest']['sender']['language']
          rescue
            viber_user_locale = 'en'
          end
          source_language = self.from_language(viber_user_locale)
          source_text = self.annotated.text
          language_code = self.get_field('translation_language').value
          target_language = CheckCldr.language_code_to_name(language_code, viber_user_locale)
          target_text = self.get_field_value('translation_text')
          { source_language: source_language, source_text: source_text, target_language: target_language, target_text: target_text, language_code: language_code.downcase }
        rescue
          ''
        end
      end
    end

    def translation_to_message_as_text
      text = ''
      if self.annotation_type == 'translation'
        m = self.translation_to_message
        if m.is_a?(Hash)
          message = [m[:source_text], '', m[:target_language].to_s + ':', m[:target_text]]
          message.unshift(m[:source_language] + ':') unless m[:source_language].blank?
          text = message.join("\n")
        end
      end
      text
    end

    def translation_to_message_as_image
      if self.annotation_type == 'translation'
        imagefilename = Bot::Viber.default.text_to_image(self.translation_to_message)
        CONFIG['checkdesk_base_url'] + '/viber/' + imagefilename + '.jpg'
      end
    end

    def self.respond_to_user(tid, success = true)
      request = Dynamic.where(id: tid).last
      return if request.nil?
      if request.get_field_value('translation_request_type') == 'viber'
        data = JSON.parse(request.get_field_value('translation_request_raw_data'))
        if success
          translation = request.annotated.get_dynamic_annotation('translation')
          unless translation.nil?
            Bot::Viber.default.send_text_message(data['sender'], translation.translation_to_message_as_text)
            Bot::Viber.default.send_image_message(data['sender'], translation.translation_to_message_as_image)
          end
        else
          message = request.annotated.get_dynamic_annotation('translation_status').get_field_value('translation_status_note')
          Bot::Viber.default.send_text_message(data['sender'], message) unless message.blank?
        end
      end
    end

    def respond_to_user(success = true)
      if !CONFIG['viber_token'].blank? && self.annotation_type == 'translation_request' && self.annotated_type == 'ProjectMedia'
        Dynamic.delay_for(1.second).respond_to_user(self.id, success)
      end
    end
    
    private

    def store_previous_status
      self.previous_translation_status = self.translation_status if self.annotation_type == 'translation_status'
    end
  end

  ProjectMedia.class_eval do
    after_create :create_first_translation_status

    alias_method :report_type_original, :report_type

    def report_type
      self.get_annotations('translation_request').any? ? 'translation_request' : self.report_type_original
    end

    private

    def create_first_translation_status
      if DynamicAnnotation::AnnotationType.where(annotation_type: 'translation_status').exists? &&
         DynamicAnnotation::FieldInstance.where(name: 'translation_status_status').exists? &&
         DynamicAnnotation::FieldInstance.where(name: 'translation_status_note').exists? &&
         DynamicAnnotation::FieldInstance.where(name: 'translation_status_approver').exists?
        user = User.current
        User.current = nil
        ts = Dynamic.new
        ts.skip_check_ability = true
        ts.annotation_type = 'translation_status'
        ts.annotated = self
        ts.set_fields = { translation_status_status: 'pending', translation_status_note: '', translation_status_approver: '{}' }.to_json
        ts.save
        User.current = user
      end
    end
  end

  # All GraphQL types can have access to the translation_statuses

  GraphqlCrudOperations.class_eval do
    singleton_class.send(:alias_method, :define_default_type_original, :define_default_type)

    def self.define_default_type(&block)
      GraphqlCrudOperations.define_default_type_original do
        field :translation_statuses, types.String do
          resolve -> (_obj, _args, _ctx) {
            fi = DynamicAnnotation::FieldInstance.where(name: 'translation_status_status').last
            return '{}' if fi.nil?
            statuses = []
            fi.settings[:statuses].each do |status|
              status[:label] = I18n.t("label_translation_status_#{status[:id]}".to_sym, default: status[:label])
              statuses << status
            end
            { label: 'translation_status', default: 'pending', statuses: statuses }.to_json 
          }
        end

        instance_eval(&block)
      end
    end
  end
end

# name: discourse-latest-replies-sql
# about: Plugin que exibe os últimos comentários usando queries SQL diretas
# version: 1.0.0
# authors: Discourse Community
# url: https://github.com/discourse/discourse-latest-replies-sql
# required_version: 2.7.0
# transpile_js: true

enabled_site_setting :latest_replies_sql_enabled

register_asset "stylesheets/latest-replies.scss"

after_initialize do
  # Configurações do plugin
  add_admin_route 'latest_replies_sql.title', 'latest-replies-sql'

  # Modelo para armazenar configurações do plugin
  class ::LatestRepliesSqlConfig
    include ActiveModel::Model
    include ActiveModel::Serialization

    attr_accessor :enabled, :comments_to_show, :polling_interval, :cache_duration,
                  :show_categories, :show_tags, :excluded_categories, :excluded_tags

    def initialize(attributes = {})
      @enabled = attributes[:enabled] || true
      @comments_to_show = attributes[:comments_to_show] || 15
      @polling_interval = attributes[:polling_interval] || 2000
      @cache_duration = attributes[:cache_duration] || 86400000 # 24 horas em ms
      @show_categories = attributes[:show_categories] || true
      @show_tags = attributes[:show_tags] || true
      @excluded_categories = attributes[:excluded_categories] || []
      @excluded_tags = attributes[:excluded_tags] || []
    end

    def self.current
      config_data = PluginStore.get("latest_replies_sql", "config") || {}
      new(config_data.symbolize_keys)
    end

    def save
      PluginStore.set("latest_replies_sql", "config", {
        enabled: @enabled,
        comments_to_show: @comments_to_show,
        polling_interval: @polling_interval,
        cache_duration: @cache_duration,
        show_categories: @show_categories,
        show_tags: @show_tags,
        excluded_categories: @excluded_categories,
        excluded_tags: @excluded_tags
      })
    end
  end

  # Controller para gerenciar as queries SQL
  class ::LatestRepliesSqlController < ::ApplicationController
    requires_login
    before_action :ensure_staff, except: [:latest_replies]

    def latest_replies
      config = LatestRepliesSqlConfig.current
      
      unless config.enabled
        render json: { error: "Plugin desabilitado" }, status: 403
        return
      end

      begin
        # Query SQL otimizada para buscar os últimos comentários
        sql = build_latest_replies_query(config)
        
        results = DB.query(sql, {
          limit: config.comments_to_show,
          excluded_categories: config.excluded_categories,
          excluded_tags: config.excluded_tags
        })

        # Processar os resultados
        processed_results = process_query_results(results, config)

        render json: {
          success: true,
          data: processed_results,
          config: {
            comments_to_show: config.comments_to_show,
            polling_interval: config.polling_interval,
            show_categories: config.show_categories,
            show_tags: config.show_tags
          }
        }

      rescue => e
        Rails.logger.error "LatestRepliesSQL Error: #{e.message}"
        render json: { 
          error: "Erro ao buscar comentários", 
          fallback_to_api: true 
        }, status: 500
      end
    end

    def config
      render json: LatestRepliesSqlConfig.current
    end

    def update_config
      config = LatestRepliesSqlConfig.current
      
      config.enabled = params[:enabled] if params.key?(:enabled)
      config.comments_to_show = params[:comments_to_show].to_i if params[:comments_to_show]
      config.polling_interval = params[:polling_interval].to_i if params[:polling_interval]
      config.cache_duration = params[:cache_duration].to_i if params[:cache_duration]
      config.show_categories = params[:show_categories] if params.key?(:show_categories)
      config.show_tags = params[:show_tags] if params.key?(:show_tags)
      config.excluded_categories = params[:excluded_categories] || []
      config.excluded_tags = params[:excluded_tags] || []

      config.save

      render json: { success: true, config: config }
    end

    def test_query
      begin
        config = LatestRepliesSqlConfig.current
        sql = build_latest_replies_query(config)
        
        start_time = Time.now
        results = DB.query(sql, { limit: 5 })
        end_time = Time.now
        
        render json: {
          success: true,
          query_time: ((end_time - start_time) * 1000).round(2),
          results_count: results.length,
          sample_data: results.first(3)
        }
      rescue => e
        render json: { 
          success: false, 
          error: e.message 
        }
      end
    end

    private

    def build_latest_replies_query(config)
      excluded_categories_condition = ""
      excluded_tags_condition = ""

      if config.excluded_categories.any?
        excluded_categories_condition = "AND c.name NOT IN (#{config.excluded_categories.map { |cat| "'#{cat}'" }.join(', ')})"
      end

      if config.excluded_tags.any?
        excluded_tags_condition = "AND NOT EXISTS (
          SELECT 1 FROM topic_tags tt2 
          INNER JOIN tags t2 ON tt2.tag_id = t2.id 
          WHERE tt2.topic_id = t.id 
          AND t2.name IN (#{config.excluded_tags.map { |tag| "'#{tag}'" }.join(', ')})
        )"
      end

      tags_select = config.show_tags ? 
        "COALESCE(ARRAY_AGG(DISTINCT tag.name) FILTER (WHERE tag.name IS NOT NULL), ARRAY[]::text[]) as tags," : 
        "ARRAY[]::text[] as tags,"

      category_select = config.show_categories ? 
        "c.name as category_name, c.color as category_color, c.text_color as category_text_color," : 
        "NULL as category_name, NULL as category_color, NULL as category_text_color,"

      <<~SQL
        SELECT 
          p.id,
          p.post_number,
          p.raw,
          p.cooked,
          p.created_at,
          p.updated_at,
          p.topic_id,
          p.user_id,
          t.title as topic_title,
          t.slug as topic_slug,
          t.category_id,
          #{category_select}
          u.username,
          u.name as display_name,
          u.avatar_template,
          #{tags_select}
          CASE 
            WHEN LENGTH(REGEXP_REPLACE(COALESCE(p.cooked, p.raw), '<[^>]*>', '', 'g')) > 200 
            THEN LEFT(REGEXP_REPLACE(COALESCE(p.cooked, p.raw), '<[^>]*>', '', 'g'), 200) || '...'
            ELSE REGEXP_REPLACE(COALESCE(p.cooked, p.raw), '<[^>]*>', '', 'g')
          END as excerpt
        FROM posts p
        INNER JOIN topics t ON p.topic_id = t.id
        INNER JOIN users u ON p.user_id = u.id
        LEFT JOIN categories c ON t.category_id = c.id
        LEFT JOIN topic_tags tt ON t.id = tt.topic_id
        LEFT JOIN tags tag ON tt.tag_id = tag.id
        WHERE 
          p.post_number > 1 
          AND p.deleted_at IS NULL
          AND t.deleted_at IS NULL
          AND t.archetype = 'regular'
          AND t.visible = true
          AND p.hidden = false
          AND u.active = true
          AND u.silenced_till IS NULL
          AND u.suspended_till IS NULL
          #{excluded_categories_condition}
          #{excluded_tags_condition}
        GROUP BY 
          p.id, p.post_number, p.raw, p.cooked, p.created_at, p.updated_at,
          p.topic_id, p.user_id, t.title, t.slug, t.category_id,
          c.name, c.color, c.text_color, u.username, u.name, u.avatar_template
        ORDER BY p.created_at DESC
        LIMIT :limit
      SQL
    end

    def process_query_results(results, config)
      results.map do |row|
        {
          post: {
            id: row.id,
            post_number: row.post_number,
            raw: row.raw,
            cooked: row.cooked,
            created_at: row.created_at,
            updated_at: row.updated_at,
            topic_id: row.topic_id,
            user_id: row.user_id,
            topic_title: row.topic_title,
            topic_slug: row.topic_slug,
            excerpt: row.excerpt,
            username: row.username,
            display_username: row.display_name,
            name: row.display_name,
            avatar_template: row.avatar_template
          },
          category: config.show_categories ? row.category_name : nil,
          category_color: config.show_categories ? row.category_color : nil,
          category_text_color: config.show_categories ? row.category_text_color : nil,
          tags: config.show_tags ? (row.tags || []) : []
        }
      end
    end

    def ensure_staff
      raise Discourse::InvalidAccess.new unless current_user&.staff?
    end
  end

  # Serializer para os dados dos comentários
  class ::LatestReplySerializer < ApplicationSerializer
    attributes :id, :post_number, :excerpt, :created_at, :topic_id, :topic_slug, 
               :topic_title, :username, :display_name, :avatar_template,
               :category_name, :category_color, :tags

    def avatar_template
      object[:post][:avatar_template]
    end

    def excerpt
      object[:post][:excerpt]
    end

    def created_at
      object[:post][:created_at]
    end

    def topic_slug
      object[:post][:topic_slug]
    end

    def username
      object[:post][:username]
    end
  end

  # Registrar as rotas
  Discourse::Application.routes.append do
    get '/latest-replies-sql' => 'latest_replies_sql#latest_replies'
    get '/admin/plugins/latest-replies-sql/config' => 'latest_replies_sql#config'
    put '/admin/plugins/latest-replies-sql/config' => 'latest_replies_sql#update_config'
    get '/admin/plugins/latest-replies-sql/test' => 'latest_replies_sql#test_query'
  end

  # Adicionar ao menu de administração
  add_admin_route 'latest_replies_sql.title', 'latest-replies-sql'

  # Registrar configurações do site
  register_site_setting_type('latest_replies_categories', 'list')
  register_site_setting_type('latest_replies_tags', 'list')

  # Hook para limpar cache quando posts são criados/atualizados
  on(:post_created) do |post, opts, user|
    if post.post_number > 1
      MessageBus.publish("/latest-replies-update", { 
        action: "new_post", 
        post_id: post.id 
      })
    end
  end

  on(:post_edited) do |post, topic_changed|
    if post.post_number > 1
      MessageBus.publish("/latest-replies-update", { 
        action: "post_edited", 
        post_id: post.id 
      })
    end
  end

  # Adicionar permissões
  add_to_class(:guardian, :can_view_latest_replies_sql?) do
    return false if !SiteSetting.latest_replies_sql_enabled
    return true if user&.staff?
    return true # Permitir para todos os usuários logados
  end

  # Registrar o plugin no sistema de plugins
  register_plugin_name 'discourse-latest-replies-sql'
end

# Configurações do site
register_site_setting('latest_replies_sql_enabled', true, type: 'bool')
register_site_setting('latest_replies_sql_comments_count', 15, type: 'integer', min: 5, max: 50)
register_site_setting('latest_replies_sql_polling_interval', 2000, type: 'integer', min: 1000, max: 30000)
register_site_setting('latest_replies_sql_show_categories', true, type: 'bool')
register_site_setting('latest_replies_sql_show_tags', true, type: 'bool')
register_site_setting('latest_replies_sql_excluded_categories', '', type: 'list')
register_site_setting('latest_replies_sql_excluded_tags', '', type: 'list')

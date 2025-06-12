# Controller para o painel de administração
class Admin::LatestRepliesSqlController < Admin::AdminController
  def index
    render json: {
      config: LatestRepliesSqlConfig.current,
      categories: Category.all.pluck(:name),
      tags: Tag.all.pluck(:name),
      stats: get_plugin_stats
    }
  end

  def update
    config = LatestRepliesSqlConfig.current
    
    permitted_params = params.permit(
      :enabled, :comments_to_show, :polling_interval, :cache_duration,
      :show_categories, :show_tags, 
      excluded_categories: [], excluded_tags: []
    )

    permitted_params.each do |key, value|
      config.send("#{key}=", value) if config.respond_to?("#{key}=")
    end

    if config.save
      # Notificar clientes sobre mudança de configuração
      MessageBus.publish("/latest-replies-config-update", {
        action: "config_updated",
        config: config
      })

      render json: { success: true, config: config }
    else
      render json: { success: false, errors: config.errors }
    end
  end

  def test_performance
    begin
      config = LatestRepliesSqlConfig.current
      
      # Teste de performance da query
      start_time = Time.now
      controller = LatestRepliesSqlController.new
      sql = controller.send(:build_latest_replies_query, config)
      results = DB.query(sql, { limit: config.comments_to_show })
      end_time = Time.now
      
      query_time = ((end_time - start_time) * 1000).round(2)
      
      # Comparar com API REST (simulado)
      api_start_time = Time.now
      posts = Post.includes(:topic, :user, topic: [:category, :tags])
                  .where('post_number > 1')
                  .where('posts.deleted_at IS NULL')
                  .joins(:topic)
                  .where('topics.deleted_at IS NULL AND topics.visible = true')
                  .order(created_at: :desc)
                  .limit(config.comments_to_show)
      api_end_time = Time.now
      
      api_time = ((api_end_time - api_start_time) * 1000).round(2)
      
      render json: {
        success: true,
        sql_query_time: query_time,
        api_query_time: api_time,
        performance_improvement: ((api_time - query_time) / api_time * 100).round(2),
        results_count: results.length,
        sample_result: results.first
      }
    rescue => e
      render json: { 
        success: false, 
        error: e.message,
        backtrace: e.backtrace.first(5)
      }
    end
  end

  def clear_cache
    # Limpar cache do plugin
    PluginStore.remove("latest_replies_sql", "cache")
    
    # Notificar clientes para limpar cache local
    MessageBus.publish("/latest-replies-cache-clear", {
      action: "cache_cleared",
      timestamp: Time.now.to_i
    })

    render json: { success: true, message: "Cache limpo com sucesso" }
  end

  def export_config
    config = LatestRepliesSqlConfig.current
    
    send_data config.to_json, 
              filename: "latest-replies-sql-config-#{Date.current}.json",
              type: 'application/json'
  end

  def import_config
    begin
      uploaded_file = params[:file]
      config_data = JSON.parse(uploaded_file.read)
      
      config = LatestRepliesSqlConfig.new(config_data.symbolize_keys)
      
      if config.save
        render json: { success: true, message: "Configuração importada com sucesso" }
      else
        render json: { success: false, errors: config.errors }
      end
    rescue JSON::ParserError
      render json: { success: false, error: "Arquivo JSON inválido" }
    rescue => e
      render json: { success: false, error: e.message }
    end
  end

  private

  def get_plugin_stats
    {
      total_posts: Post.where('post_number > 1').count,
      total_topics: Topic.where(visible: true).count,
      active_users: User.where(active: true).count,
      plugin_version: "1.0.0",
      last_cache_update: PluginStore.get("latest_replies_sql", "last_update") || "Nunca"
    }
  end
end

<script type="text/discourse-plugin" version="0.11.3">
api.onPageChange(() => {\
  if (window.location.pathname !== "/") return;
  
  const container = document.querySelector(".category-list");
  if (!container || window.latestRepliesInitialized) return;
  
  window.latestRepliesInitialized = true;

  // Configurações centralizadas
  const CONFIG = {\
    POLLING_INTERVAL: 2000,
    COMMENTS_TO_SHOW: 15,
    CACHE_DURATION: 24 * 60 * 60 * 1000,
    CACHE_KEYS: {\
      DATA: "discourse_latest_replies_data",
      TIMESTAMP: "discourse_latest_replies_timestamp",
      LAST_ID: "discourse_latest_replies_last_id"
    }
  };

  class LatestRepliesManager {\
    constructor() {\
      this.lastSeenPostId = parseInt(localStorage.getItem(CONFIG.CACHE_KEYS.LAST_ID) || "0");
      this.pollingIntervalId = null;
      this.isLoading = false;
    }

    // Função melhorada de timeAgo com mais precisão
    timeAgo(dateString) {\
      const now = new Date();
      const postDate = new Date(dateString);
      const diffMs = now - postDate;

      const seconds = Math.floor(diffMs / 1000);
      const minutes = Math.floor(seconds / 60);
      const hours = Math.floor(minutes / 60);
      const days = Math.floor(hours / 24);
      const weeks = Math.floor(days / 7);
      const months = Math.floor(days / 30);

      if (months > 0) return `há ${months} mês${months > 1 ? "es" : ""}`;
      if (weeks > 0) return `há ${weeks} semana${weeks > 1 ? "s" : ""}`;
      if (days > 0) return `há ${days} dia${days > 1 ? "s" : ""}`;
      if (hours > 0) return `há ${hours} hora${hours > 1 ? "s" : ""}`;
      if (minutes > 0) return `há ${minutes} minuto${minutes > 1 ? "s" : ""}`;
      if (seconds > 30) return `há ${seconds} segundo${seconds > 1 ? "s" : ""}`;
      return "agora mesmo";
    }

    // Cache management melhorado
    getCachedData() {
      try {\
        const cachedData = localStorage.getItem(CONFIG.CACHE_KEYS.DATA);
        const cacheTimestamp = localStorage.getItem(CONFIG.CACHE_KEYS.TIMESTAMP);
        
        if (!cachedData || !cacheTimestamp) return null;
        
        const now = Date.now();
        if (now - parseInt(cacheTimestamp) >= CONFIG.CACHE_DURATION) {
          this.clearCache();\
          return null;
        }
        
        return JSON.parse(cachedData);
      } catch (error) {
        this.clearCache();\
        return null;
      }
    }

    setCachedData(data) {
      try {\
        localStorage.setItem(CONFIG.CACHE_KEYS.DATA, JSON.stringify(data));
        localStorage.setItem(CONFIG.CACHE_KEYS.TIMESTAMP, Date.now().toString());
      } catch (error) {
        // Silently fail
      }
    }

    clearCache() {
      Object.values(CONFIG.CACHE_KEYS).forEach(key => {
        localStorage.removeItem(key);
      });
    }
\
    // Executa query SQL via endpoint customizado
    async executeSQLQuery(query, params = []) {
      try {\
        const response = await fetch('/admin/plugins/explorer/queries/run', {
          method: 'POST',\
          headers: {
            'Content-Type': \'application/json',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
          },
          body: JSON.stringify({
            sql: query,\
            params: params
          })
        });

        if (!response.ok) {\
          throw new Error(`SQL Query failed: ${response.status}`);
        }

        const result = await response.json();
        return result.rows || [];
      } catch (error) {
        console.error('SQL Query Error:', error);\
        return [];
      }
    }

    async loadLatestReplies(silent = false, forceRefresh = false) {\
      if (this.isLoading) return;
      
      // Verificar cache primeiro
      if (!forceRefresh) {\
        const cachedData = this.getCachedData();
        if (cachedData) {
          this.renderLatestReplies(cachedData, false);\
          if (!silent) return;
        }
      }

      this.isLoading = true;

      try {
        // Query SQL para buscar os últimos posts/comentários\
        const latestPostsQuery = `
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
            c.name as category_name,
            c.color as category_color,
            u.username,
            u.name as display_name,
            u.avatar_template,
            ARRAY_AGG(DISTINCT tag.name) FILTER (WHERE tag.name IS NOT NULL) as tags
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
          GROUP BY 
            p.id, p.post_number, p.raw, p.cooked, p.created_at, p.updated_at,
            p.topic_id, p.user_id, t.title, t.slug, t.category_id,
            c.name, c.color, u.username, u.name, u.avatar_template
          ORDER BY p.created_at DESC
          LIMIT $1
        `;

        const posts = await this.executeSQLQuery(latestPostsQuery, [CONFIG.COMMENTS_TO_SHOW]);

        if (posts.length === 0) return;

        // Processar os resultados
        const results = posts.map(row => {
          // Extrair excerpt do conteúdo HTML\
          const tempDiv = document.createElement('div');
          tempDiv.innerHTML = row[3] || row[2] || ''; // cooked ou raw
          const excerpt = tempDiv.textContent || tempDiv.innerText || '';

          return {
            post: {\
              id: row[0],\
              post_number: row[1],
              raw: row[2],
              cooked: row[3],
              created_at: row[4],
              updated_at: row[5],
              topic_id: row[6],
              user_id: row[7],
              topic_title: row[8],
              topic_slug: row[9],
              excerpt: excerpt.substring(0, 200),
              username: row[12],
              display_username: row[13],
              name: row[13],
              avatar_template: row[14]
            },
            category: row[11], // category_name
            category_color: row[15],
            tags: row[16] || []
          };
        });

        const maxId = Math.max(...results.map(item => item.post.id));
        const hasNewPosts = maxId > this.lastSeenPostId;

        if (hasNewPosts) {
          this.lastSeenPostId = maxId;\
          localStorage.setItem(CONFIG.CACHE_KEYS.LAST_ID, this.lastSeenPostId.toString());
        }

        this.setCachedData(results);
        this.renderLatestReplies(results, hasNewPosts || forceRefresh);

      } catch (error) {
        console.error('Error loading latest replies:', error);
        \
        // Fallback para API REST se SQL falhar
        await this.loadLatestRepliesFallback(silent, forceRefresh);
      } finally {
        this.isLoading = false;
      }\
    }

    // Fallback para API REST caso SQL não funcione
    async loadLatestRepliesFallback(silent = false, forceRefresh = false) {
      try {\
        const response = await fetch("/posts.json?order=created");
        if (!response.ok) return;
        
        const data = await response.json();
        
        const replies = data.latest_posts
          ?.filter(p => p.post_number > 1 && !p.topic_slug?.includes("private-message"))
          ?.slice(0, CONFIG.COMMENTS_TO_SHOW) || [];

        if (replies.length === 0) return;

        const maxId = Math.max(...replies.map(post => post.id));
        const hasNewPosts = maxId > this.lastSeenPostId;

        if (hasNewPosts) {
          this.lastSeenPostId = maxId;\
          localStorage.setItem(CONFIG.CACHE_KEYS.LAST_ID, this.lastSeenPostId.toString());
        }

        // Buscar dados dos tópicos em paralelo
        const topicPromises = replies.map(async (post) => {
          try {\
            const response = await fetch(`/t/${post.topic_id}.json`);
            if (!response.ok) return { category_id: null, category_name: null, tags: [] };
            
            const topic = await response.json();
            return topic;
          } catch (error) {
            return { category_id: null, category_name: null, tags: [] };
          }
        });

        const topics = await Promise.all(topicPromises);
        
        const results = replies.map((post, index) => ({
          post,
          category: topics[index]?.category_name || null,
          tags: topics[index]?.tags || []
        }));

        this.setCachedData(results);
        this.renderLatestReplies(results, hasNewPosts || forceRefresh);

      } catch (error) {
        console.error('Fallback API also failed:', error);
      }
    }

    renderLatestReplies(results, animate = false) {
      if (!results?.length) return;

      const rows = results.map(({ post, category, tags, category_color }) => {
        const url = `/t/${post.topic_slug}/${post.topic_id}/${post.post_number}`;
        const avatarUrl = post.avatar_template?.replace("{size}", "45") || "";
        const excerpt = this.sanitizeAndTruncate(post.excerpt || post.topic_title, 120);
        const timePosted = this.timeAgo(post.created_at);
        const fullDate = new Date(post.created_at).toLocaleString('pt-BR');
        const username = post.username || 'Usuário';
        const displayName = post.display_username || post.name || username;

        const categoryStyle = category_color ? 
          `background: #${category_color}; color: white;` : 
          `background: var(--primary-low); color: var(--primary);`;

        const categoryHtml = category
          ? `<span class="category-badge" style="
              font-size: 0.85em; 
              ${categoryStyle}
              padding: 2px 8px;
              border-radius: 12px;
              margin-right: 8px;
            ">${category}</span>` : '';

        const tagsHtml = tags && tags.length > 0 
          ? tags.slice(0, 3).map(tag => `
              <span class="discourse-tag" style="
                background: var(--primary-low);
                color: var(--primary-medium);
                padding: 2px 6px;
                border-radius: 3px;
                font-size: 0.8em;
                margin-right: 2px;
              ">${tag}</span>
            `).join("") : '';

        return `
          <tr class="topic-list-item latest-reply-item" 
              data-post-id="${post.id}" 
              style="
                transition: background-color 0.2s ease;
                border-bottom: 1px solid var(--primary-low);
              "
              onmouseover="this.style.backgroundColor='var(--highlight-low)'"
              onmouseout="this.style.backgroundColor='transparent'">
            <td class="main-link clearfix" style="padding: 12px;">
              <div style="display: flex; align-items: flex-start; gap: 12px;">
                <div style="flex-shrink: 0;">
                  <a class="avatar-link" href="/u/${username}" title="Ver perfil de ${displayName}">
                    <img loading="lazy" 
                         width="45" 
                         height="45" 
                         src="${avatarUrl}" 
                         class="avatar" 
                         alt="Avatar de ${displayName}"
                         style="border-radius: 50%;">
                  </a>
                </div>
                <div style="flex: 1; min-width: 0;">
                  <div style="margin-bottom: 8px;">
                    <a href="${url}" 
                       class="title raw-link" 
                       style="
                         font-weight: 500;
                         color: var(--primary);
                         text-decoration: none;
                         line-height: 1.4;
                       "
                       title="${excerpt}">${excerpt}</a>
                  </div>
                  <div style="
                    display: flex; 
                    flex-wrap: wrap; 
                    align-items: center; 
                    gap: 8px; 
                    font-size: 0.85em;
                    color: var(--primary-medium);
                  ">
                    <a href="/u/${username}" 
                       style="
                         color: #1a9da9;
                         text-decoration: none;
                         font-weight: 600;
                         font-size: 0.9em;
                         display: flex;
                         align-items: center;
                         gap: 4px;
                         margin-left: -6px;
                       "
                       title="Ver perfil de ${displayName}">
                      <i class="fa fa-user" style="font-size: 0.8em;"></i>
                      @${username}
                    </a>
                    ${categoryHtml}
                    ${tagsHtml}
                    <span style="
                      color: var(--primary-medium);
                      margin-left: auto;
                      display: flex;
                      align-items: center;
                      gap: 4px;
                    " title="${fullDate}">
                      <i class="fa fa-clock-o"></i>
                      ${timePosted}
                    </span>
                  </div>
                </div>
              </div>
            </td>
          </tr>
        `;
      }).join("");

      // Remove container existente
      const existingContainer = document.querySelector(".latest-replies-container");
      if (existingContainer) {
        existingContainer.remove();
      }

      const latestRepliesContainer = document.createElement("div");
      latestRepliesContainer.className = "latest-replies-container";
      latestRepliesContainer.style.cssText = `
        margin-top: 2em;
        background: var(--secondary);
        border-radius: 3px;
        overflow: hidden;
        border: 1px solid var(--secondary);
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      `;

      latestRepliesContainer.innerHTML = `
        <table class="topic-list category-topic-list" style="margin: 0;">
          <thead>
            <tr>
              <th class="default" style="
                font-size: 1.1em; 
                font-weight: 600;
                padding: 16px;
                background: var(--secondary);
                border-bottom: 2px solid var(--primary-low);
              ">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" style="margin-right: 8px; vertical-align: middle;">
                  <path d="M12,3C6.5,3 2,6.58 2,11C2.05,13.15 3.06,15.17 4.75,16.5C4.75,17.1 4.33,18.67 2,21C4.37,20.89 6.64,20 8.47,18.5C9.61,18.83 10.81,19 12,19C17.5,19 22,15.42 22,11C22,6.58 17.5,3 12,3M12,17C7.58,17 4,14.31 4,11C4,7.69 7.58,5 12,5C16.42,5 20,7.69 20,11C20,14.31 16.42,17 12,17Z" />
                </svg>
                últimos comentários (SQL)
                <span style="
                  font-size: 0.8em;
                  font-weight: normal;
                  color: var(--primary-medium);
                  margin-left: 8px;
                ">(${results.length})</span>
              </th>
            </tr>
          </thead>
          <tbody id="latest-replies-tbody">
            ${rows}
          </tbody>
        </table>
      `;

      container.parentNode.insertBefore(latestRepliesContainer, container.nextSibling);

      // Animação suave se necessário
      if (animate) {
        latestRepliesContainer.style.opacity = "0";
        latestRepliesContainer.style.transform = "translateY(10px)";
        
        requestAnimationFrame(() => {
          latestRepliesContainer.style.transition = "opacity 0.3s ease, transform 0.3s ease";
          latestRepliesContainer.style.opacity = "1";
          latestRepliesContainer.style.transform = "translateY(0)";
        });
      }
    }

    sanitizeAndTruncate(text, maxLength) {
      if (!text) return '';
      
      // Remove HTML tags
      const cleaned = text.replace(/<\/?[^>]+(>|$)/g, "");
      
      if (cleaned.length <= maxLength) return cleaned;
      
      // Truncate at word boundary
      const truncated = cleaned.slice(0, maxLength);
      const lastSpace = truncated.lastIndexOf(' ');
      
      return (lastSpace > maxLength * 0.8 ? truncated.slice(0, lastSpace) : truncated) + '...';
    }

    startPolling() {
      this.pollingIntervalId = setInterval(() => {
        if (window.location.pathname === "/" && !this.isLoading) {
          this.loadLatestReplies(true, false);
        }
      }, CONFIG.POLLING_INTERVAL);
    }

    stopPolling() {
      if (this.pollingIntervalId) {
        clearInterval(this.pollingIntervalId);
        this.pollingIntervalId = null;
      }
    }

    init() {
      this.loadLatestReplies(false, false);
      this.startPolling();
    }

    destroy() {
      this.stopPolling();
      window.latestRepliesInitialized = false;
    }
  }

  // Inicializar o manager
  const manager = new LatestRepliesManager();
  manager.init();

  // Cleanup ao mudar de página
  api.onPageChange((url) => {
    if (url !== "/") {
      manager.destroy();
    }
  });

  // Cleanup ao sair da página
  window.addEventListener('beforeunload', () => {
    manager.destroy();
  });
});
</script>

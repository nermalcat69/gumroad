# frozen_string_literal: true

module ApplicationHelper
  def load_pack(page)
    render("shared/pack_setup", page:)
  end

  def s3_bucket_url
    "https://s3.amazonaws.com/#{S3_BUCKET}"
  end

  def default_footer_content
    safe_join(
      [
        "Powered by",
        tag.span("Gumroad", class: "logo-full", aria: { label: "Gumroad" })
      ],
      " "
    )
  end

  def current_user_props(current_user, impersonated_user)
    {
      name: current_user.display_name,
      avatar_url: current_user.avatar_url,
      impersonated_user: impersonated_user.present? ? {
        name: impersonated_user.display_name,
        avatar_url: impersonated_user.avatar_url
      } : nil
    }
  end

  def number_to_si(number)
    number_to_human(
      number,
      units: { unit: "", thousand: "K", million: "M", billion: "B", trillion: "T" },
      precision: 1,
      significant: false,
      round_mode: :truncate,
      format: "%n%u"
    )
  end

  def body_background_class
    ""
  end

  def discover_layout_context(params, request)
    is_discover_layout = params[:layout] == 'discover'
    is_discover_route = request.path.start_with?('/discover')
    has_taxonomy = params[:from].present?

    if is_discover_layout || is_discover_route
      has_taxonomy ? 'discover-with-taxonomy' : 'discover-without-taxonomy'
    else
      'default'
    end
  end
end

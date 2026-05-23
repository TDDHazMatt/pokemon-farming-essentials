module Input
  USE      = C
  BACK     = B
  ACTION   = A
  JUMPUP   = X
  JUMPDOWN = Y
  SPECIAL  = Z
  AUX1     = L
  AUX2     = R

  VK_TAB = 0x09
  @_get_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") rescue nil

  # Returns true while Tab is physically held down.
  def self.tab_held?
    return @_get_key_state && (@_get_key_state.call(VK_TAB) & 0x8000) != 0
  end

  unless defined?(update_KGC_ScreenCapture)
    class << Input
      alias update_KGC_ScreenCapture update
    end
  end

  def self.update
    update_KGC_ScreenCapture
    pbScreenCapture if trigger?(Input::F8)
  end
end

module Mouse
  module_function

  # Returns the position of the mouse relative to the game window.
  def getMousePos(catch_anywhere = false)
    return nil unless Input.mouse_in_window || catch_anywhere
    return Input.mouse_x, Input.mouse_y
  end
end

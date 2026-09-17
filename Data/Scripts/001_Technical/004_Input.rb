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
  VK_D   = 0x44
  @_get_key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") rescue nil
  @_d_held_last_frame = false

  # Returns true while Tab is physically held down.
  def self.tab_held?
    return @_get_key_state && (@_get_key_state.call(VK_TAB) & 0x8000) != 0
  end

  # Returns true on the frame D is physically pressed down (not held) - there's
  # no abstracted RGSS button for a raw letter key, so this goes straight to
  # Win32 GetAsyncKeyState like tab_held? above, but tracks the previous
  # frame's state itself to give trigger (edge-detected), not held, semantics.
  def self.trigger_d?
    down = @_get_key_state && (@_get_key_state.call(VK_D) & 0x8000) != 0
    triggered = down && !@_d_held_last_frame
    @_d_held_last_frame = down
    return triggered
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

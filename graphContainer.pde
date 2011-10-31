class GraphContainer extends View {
  
  float CHECKBOX_X ;
  float CHECKBOX_Y ;
  float CHECKBOX_W ;
  float CHECKBOX_H ;
  
  String title;
  
  GraphContainer(float x_, float y_, float w_, float h_)
  {
    super(x_, y_, w_, h_);
    textFont(font,normalFontSize);
      
    graphView = new GraphView(0, 0, w - 160, h-5);
    this.subviews.add(graphView);
    
    graphModeList = new ListBox(w - 160, 25, 160, 160, graphView.modesDataSource());
    this.subviews.add(graphModeList);
    
    CHECKBOX_X = w - 160;
    CHECKBOX_Y = 220;
    CHECKBOX_W = 160;
    CHECKBOX_H = 150;  
  }
  
  void addCheckboxes(){
      int i = 0;
      for (Entry<SightingType, Checkbox> entry : settingsView.typeCheckboxMap.entrySet()) {
        int y_delta = (i % 7) * 20;
        entry.getValue().x = CHECKBOX_X + 10;
        entry.getValue().y = CHECKBOX_Y + y_delta + 9;
        subviews.add(entry.getValue());
        i++;
      }
      
  }
  
  void removeCheckboxes(){
     for (Entry<SightingType, Checkbox> entry : settingsView.typeCheckboxMap.entrySet()) {
      subviews.remove(entry.getValue());
    }
  }
  
   void drawContent()
  {
    textSize(normalFontSize);
    fill(viewBackgroundColor);
    stroke(viewBackgroundColor);
    rect(0,0, w, h);
    fill(textColor);
    textAlign(LEFT,TOP);
    title = " Type of UFO ";
    text(title,CHECKBOX_X,CHECKBOX_Y - 5);
    stroke(textColor);
    
    line(CHECKBOX_X + textWidth(title)+5,CHECKBOX_Y,CHECKBOX_X+CHECKBOX_W,CHECKBOX_Y);
    line(CHECKBOX_X,CHECKBOX_Y,CHECKBOX_X,CHECKBOX_H + CHECKBOX_Y);
    line(CHECKBOX_X,CHECKBOX_H + CHECKBOX_Y,CHECKBOX_X+CHECKBOX_W,CHECKBOX_H + CHECKBOX_Y);
    line(CHECKBOX_X+CHECKBOX_W,CHECKBOX_Y,CHECKBOX_X+CHECKBOX_W,CHECKBOX_H + CHECKBOX_Y);
        
  }
  
}


/*
 * Copyright (C) 2011 United States Government as represented by the Administrator of the
 * National Aeronautics and Space Administration.
 * All Rights Reserved.
 */
package gov.nasa.worldwind.layers;

import gov.nasa.worldwind.render.DeclutteringTextRenderer;
import gov.nasa.worldwind.render.DrawContext;
import gov.nasa.worldwind.render.GeographicText;
import gov.nasa.worldwind.util.Logging;

import java.util.Collection;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * Layer to support objects of type {@link GeographicText}
 * 
 * @author Bruno Spyckerelle
 * @version $Id$
 */
public class TextLayer extends AbstractLayer
{
    private final DeclutteringTextRenderer textRenderer;
    private final Collection<GeographicText> geographicTexts;

    public TextLayer()
    {
        this.textRenderer = new DeclutteringTextRenderer();
        this.geographicTexts = new ConcurrentLinkedQueue<GeographicText>();
    }

    /**
     * Adds the specified <code>text</code> to this layer's internal collection.
     * @param text {@link GeographicText} to add.
     * @throws IllegalArgumentException If <code>text</code> is null.
     */
    public void addGeographicText(GeographicText text)
    {
        if (text == null)
        {
            String msg = "nullValue.GeographicTextIsNull";
            Logging.logger().severe(msg);
            throw new IllegalArgumentException(msg);
        }
        this.geographicTexts.add(text);
    }

    public void addGeographicTexts(Iterable<? extends GeographicText> texts)
    {
        if (texts == null)
        {
            String msg = Logging.getMessage("nullValue.IterableIsNull");
            Logging.logger().severe(msg);
            throw new IllegalArgumentException(msg);
        }
        for (GeographicText text : texts)
        {
            if (text != null)
            {
                this.geographicTexts.add(text);
            }
        }
    }

    public void removeGeographicText(GeographicText text)
    {
        if (text == null)
        {
            String msg = "nullValue.GeographicTextIsNull";
            Logging.logger().severe(msg);
            throw new IllegalArgumentException(msg);
        }
        this.geographicTexts.remove(text);
    }
    
    public void removeGeographicTexts(Iterable<? extends GeographicText> texts)
    {
        if (texts == null)
        {
            String msg = Logging.getMessage("nullValue.IterableIsNull");
            Logging.logger().severe(msg);
            throw new IllegalArgumentException(msg);
        }
        for (GeographicText text : texts)
        {
            if (text != null)
            {
                this.geographicTexts.remove(text);
            }
        }
    }

    public void removeAllGeographicTexts()
    {
        this.geographicTexts.clear();
    }

    public Iterable<GeographicText> getActiveGeographicTexts()
    {
        return this.geographicTexts;
    }

    @Override
    protected void doRender(DrawContext dc)
    {
        this.textRenderer.render(dc, getActiveGeographicTexts());
    }
}